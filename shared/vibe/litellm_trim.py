"""
LiteLLM proxy pre-call hook: trim oversize prompts before they hit Mistral.

Problem this solves
-------------------
Claude Code (cc-vibe / cc-local / cc-obelisk) packs system prompt + every
loaded tool schema + transcript + file reads into one request. Mistral
models cap at 131072 tokens total. A long session crosses the limit and
the upstream returns:

    400 ... Prompt contains 131761 tokens ... too large for model
    with 131072 maximum context length

This hook runs BEFORE the request leaves the proxy. If the message list
is over the per-model target, it drops the oldest non-system, non-tail
messages and inserts a single `[N earlier messages trimmed ...]` system
marker so the model knows context is incomplete (and may probe to
re-establish it).

Wiring
------
Loaded via ~/.vibe/litellm-config.yaml:

    litellm_settings:
      callbacks: litellm_trim.proxy_handler_instance

The litellm proxy runs with cwd=~/.vibe (set by the launchd plist /
systemd unit), so this file is importable as the top-level module
`litellm_trim`. The same wiring is used on both the local proxy and
any remote LiteLLM gateway with this file deployed alongside its config.

Tunables (env vars, all optional)
---------------------------------
- LITELLM_TRIM_TARGET_TOKENS  per-model input budget, default 120000
                              (leaves ~11000 for the response on a 131072 model)
- LITELLM_TRIM_KEEP_TAIL      messages from the end that are NEVER dropped,
                              default 6 (current user turn + a few prior)
- LITELLM_TRIM_LOG            path to append a one-line audit log per trim,
                              default ~/.vibe/logs/trim.log
- LITELLM_TRIM_DISABLE        set to "1" to bypass entirely (debugging)
"""

from __future__ import annotations

import os
import json
import time
import traceback
from pathlib import Path
from typing import Any, Optional

from litellm import token_counter
from litellm.integrations.custom_logger import CustomLogger


TARGET_TOKENS = int(os.environ.get("LITELLM_TRIM_TARGET_TOKENS", "120000"))
KEEP_TAIL = int(os.environ.get("LITELLM_TRIM_KEEP_TAIL", "6"))
LOG_PATH = Path(
    os.environ.get("LITELLM_TRIM_LOG", str(Path.home() / ".vibe/logs/trim.log"))
)
DISABLED = os.environ.get("LITELLM_TRIM_DISABLE") == "1"
DEBUG = os.environ.get("LITELLM_TRIM_DEBUG") == "1"

# Safety margin subtracted from TARGET to account for the chat-format
# overhead (role tags, tool-call wrappers) that token_counter approximates.
SAFETY_MARGIN = 1500


def _log(record: dict) -> None:
    try:
        LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
        record["ts"] = int(time.time())
        with LOG_PATH.open("a") as fh:
            fh.write(json.dumps(record, default=str) + "\n")
    except Exception:
        pass


def _count(messages, model: str) -> int:
    try:
        return token_counter(model=model, messages=messages)
    except Exception:
        # token_counter can fail on unknown model names; estimate by char count / 3.5
        total_chars = 0
        for m in messages:
            content = m.get("content")
            if isinstance(content, str):
                total_chars += len(content)
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict):
                        total_chars += len(json.dumps(block, default=str))
            else:
                total_chars += len(str(content)) if content else 0
        return total_chars // 3


MIN_TAIL = 2  # never drop below this — preserves at least the current user turn


def _trim(messages: list[dict], model: str, target: int) -> tuple[list[dict], int, int, int]:
    """
    Returns (new_messages, dropped_count, original_tokens, new_tokens).

    Strategy:
      1. Always keep every system message (they hold tool schemas and policy).
      2. Try to keep the last KEEP_TAIL non-system messages.
      3. Drop the OLDEST non-system, non-tail messages one at a time
         until total tokens fits under (target - SAFETY_MARGIN).
      4. If head is exhausted and we still don't fit, shrink tail from
         oldest-tail-end until tail == MIN_TAIL.
      5. Insert a single system marker noting how many were dropped.
      6. If even sys + marker + MIN_TAIL tail can't fit, return what we
         have and let the upstream raise — context_window_fallbacks
         (configured in litellm-config.yaml) takes it from there.
    """
    original = _count(messages, model)
    if original <= target - SAFETY_MARGIN:
        return messages, 0, original, original

    sys_msgs = [m for m in messages if m.get("role") == "system"]
    other = [m for m in messages if m.get("role") != "system"]

    if len(other) <= MIN_TAIL:
        # Nothing droppable — single huge message. Caller will hit fallback.
        return messages, 0, original, original

    desired_tail = min(KEEP_TAIL, len(other))
    tail = other[-desired_tail:]
    head = list(other[:-desired_tail])

    dropped = 0
    budget = target - SAFETY_MARGIN

    def _build(head_list, tail_list, drop_count):
        marker = {
            "role": "system",
            "content": (
                f"[{drop_count} earlier message(s) trimmed to fit the "
                f"{target}-token context window]"
            ),
        }
        return sys_msgs + [marker] + head_list + tail_list

    # Phase 1: drop oldest head messages until fit.
    while head:
        candidate = _build(head, tail, dropped + 1)
        if _count(candidate, model) <= budget:
            return candidate, dropped + 1, original, _count(candidate, model)
        head.pop(0)
        dropped += 1

    # Phase 2: head is empty; shrink tail from its oldest end (tail[0])
    # while keeping at least MIN_TAIL messages so the current user turn
    # and one prior turn always survive.
    while len(tail) > MIN_TAIL:
        candidate = _build([], tail, dropped + 1)
        if _count(candidate, model) <= budget:
            return candidate, dropped + 1, original, _count(candidate, model)
        tail.pop(0)
        dropped += 1

    # Phase 3: at MIN_TAIL — final attempt, then give up to fallback.
    candidate = _build([], tail, dropped)
    return candidate, dropped, original, _count(candidate, model)


class TrimHandler(CustomLogger):
    """LiteLLM proxy hook that trims oversize prompts before dispatch."""

    async def async_pre_call_hook(
        self,
        user_api_key_dict: Any,
        cache: Any,
        data: dict,
        call_type: str,
    ) -> Optional[dict]:
        if DISABLED:
            return data

        if DEBUG:
            try:
                keys = sorted(list(data.keys()))[:20]
                _log({"event": "hook_entered", "call_type": call_type, "data_keys": keys,
                      "has_messages": "messages" in data, "model": data.get("model")})
            except Exception:
                pass

        # Don't filter by call_type — LiteLLM uses different strings for
        # /v1/chat/completions (completion/acompletion) and /v1/messages
        # (anthropic_messages) and we want to trim both. Just probe for
        # the messages payload and skip if it isn't there.
        messages = data.get("messages")
        if not messages or not isinstance(messages, list):
            return data

        model = data.get("model") or "mistral/mistral-medium-latest"

        # Anthropic /v1/messages puts the system prompt OUTSIDE the messages
        # list (top-level `system` key). For token accounting we synthesize
        # an equivalent system message so trim sees the true input size.
        # The system value itself is never modified.
        system = data.get("system")
        if system:
            if isinstance(system, list):
                sys_text = "".join(
                    (b.get("text") or "") if isinstance(b, dict) else str(b)
                    for b in system
                )
            else:
                sys_text = str(system)
            messages_for_count = [
                {"role": "system", "content": sys_text}
            ] + messages
        else:
            messages_for_count = messages

        try:
            new_for_count, dropped, before, after = _trim(
                messages_for_count, model, TARGET_TOKENS
            )
            # _trim may insert its own [trimmed] marker as a system message;
            # we need to strip the synthetic system at index 0 and rewrite
            # the original messages list, leaving data["system"] untouched.
            if dropped > 0:
                # Pull out the trim marker (any system msg containing "trimmed to fit")
                # so it ends up appended to the system string instead of being
                # injected as a system message Mistral may not accept.
                new_messages = []
                marker_text = None
                for i, m in enumerate(new_for_count):
                    role = m.get("role")
                    content = m.get("content")
                    if role == "system" and isinstance(content, str):
                        if "trimmed to fit" in content:
                            marker_text = content
                            continue
                        # Skip the synthetic system we prepended; keep any
                        # OTHER system messages (rare in Anthropic format
                        # but possible after conversion).
                        if system and i == 0 and content == sys_text:
                            continue
                    new_messages.append(m)
                if marker_text and system:
                    # Append marker to system string so it stays in-band
                    if isinstance(system, list):
                        data["system"] = system + [{"type": "text", "text": "\n\n" + marker_text}]
                    else:
                        data["system"] = str(system) + "\n\n" + marker_text
                elif marker_text:
                    new_messages.insert(0, {"role": "system", "content": marker_text})
                new_messages_final = new_messages
            else:
                new_messages_final = messages
        except Exception as exc:  # pragma: no cover - defensive
            _log({
                "event": "trim_error",
                "model": model,
                "error": str(exc),
                "trace": traceback.format_exc().splitlines()[-3:],
            })
            return data

        if dropped > 0:
            data["messages"] = new_messages_final
            _log({
                "event": "trimmed",
                "model": model,
                "tokens_before": before,
                "tokens_after": after,
                "messages_dropped": dropped,
                "messages_in": len(messages),
                "messages_out": len(new_messages_final),
                "target": TARGET_TOKENS,
            })
        elif before > TARGET_TOKENS - SAFETY_MARGIN:
            # Couldn't drop anything (system+tail alone exceeds budget).
            # Log it so the operator can see fallback is doing the work.
            _log({
                "event": "untrimmable",
                "model": model,
                "tokens": before,
                "messages": len(messages),
                "note": "single message or system+tail exceeds budget; relying on context_window_fallbacks",
            })

        return data


proxy_handler_instance = TrimHandler()
