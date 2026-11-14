# Claude Code with the Lumo chat gateway

`cc-lumo` launches Claude Code through a temporary, loopback-only LiteLLM gateway
and a small compatibility bridge to `https://chat.untitledstartup.xyz/api`.
The zsh alias `claude-lumo` launches the same command. Neither changes the
current shell's Anthropic routing or the existing `cc-vibe`/`cc-local` setup.

```sh
cc-lumo --check                 # check the credential and list accessible models
cc-lumo                         # interactive Claude Code, using lumo-lite
cc-lumo -p 'Explain this code'  # normal Claude arguments are forwarded
cc-lumo --read-only             # Read, Grep, and Glob only; smaller requests
cc-lumo --tools default         # explicitly request Claude's normal tool set

# Only if this gateway and account expose the model:
CLAUDE_LUMO_MODEL=lumo-max cc-lumo --check
CLAUDE_LUMO_MODEL=lumo-max cc-lumo
```

The default is `lumo-lite`, the model currently available to this account. The
launcher checks the model list before launching and **does not silently switch
models** if the requested ID is unavailable. The check establishes only that
the model is listed; it does not prove inference or tool use. On this Mac,
`claude-lumo` is available in new interactive zsh sessions, or after sourcing
`~/Git/dotfiles/shared/zsh/claude-aliases.zsh`.

The default is Claude Code's normal tool selection and permissions. The optional
`--read-only` profile restricts the tool set to Read, Grep, and Glob; it also
reduces request size. An explicit `--tools` selection is passed through.

## Setup on another device

The source is `shared/bin/cc-lumo`; put that executable on `PATH`, install `uv`
and Claude Code, then create its dedicated environment:

```sh
uv venv "$HOME/.local/share/claude-lumo/venv"
uv pip install --python "$HOME/.local/share/claude-lumo/venv/bin/python" 'litellm[proxy]==1.102.1'
cc-lumo --setup-key              # hidden prompt; creates a private file
cc-lumo --check
```

The key is in `~/.config/claude-lumo/api-key` with mode 600, outside the repo
and outside the synced `~/.vibe` configuration. `CLAUDE_LUMO_API_KEY` is an
optional process-environment override. Setup replaces the saved key; it does
not change the Signal bot's copy. Rotate both independently if that shared key
is revoked. Do not put it in shell history, arguments, source control, or logs.

## Hermes and OpenCode (direct, no bridge)

Hermes and OpenCode call the gateway directly as an OpenAI-compatible provider
named `lumo` (`https://chat.untitledstartup.xyz/api`, models `lumo-max` and
`lumo-lite`). Neither goes through `cc-lumo` or Claude Code.

- **OpenCode:** `shared/opencode/opencode.json` defines `providers.lumo`. Its key
  comes from `{file:~/.config/claude-lumo/api-key}`. Run
  `python3 scripts/install_opencode.py`, then `opencode service restart`, and use
  `opencode run -m lumo/lumo-max …`.
- **Hermes:** a named provider holding the key as `api_key: ${LUMO_API_KEY}`,
  with the value in the Hermes home's `.env`:
  ```yaml
  providers:
    lumo:
      api: https://chat.untitledstartup.xyz/api
      api_key: ${LUMO_API_KEY}
      transport: chat_completions
      discover_models: false
      models: {lumo-max: {context_length: 128000}, lumo-lite: {context_length: 128000}}
  ```
  Switch to it with `/model` or `--provider custom:lumo -m lumo-max`.
- **Pin Hermes' auxiliary tasks to another provider**
  (`auxiliary.title_generation`, `compression`, `vision`).
  - Streaming replies are normal SSE.
  - A non-streaming reply is a JSON string that contains the JSON object, and
    clients reject it ("LLM returned invalid response (type=str)").
  - Hermes streams its main turns but not its auxiliary calls.
  - OpenCode's turns worked as is.

Tested 2026-11-14:
- **Hermes:** each of three server Hermes bots made a `read_file` tool call
  through `lumo` and returned the exact contents. The bots' default models were
  unchanged.
- **OpenCode 2.2.5:** `lumo/lumo-max` made a read tool call and returned the
  exact marker.
- **Prompt size:** the gateway accepted prompts of 112K, 175K and 250K tokens
  (`lumo-lite`) and 175K (`lumo-max`), and recalled a word from the start of
  each. 128K is a conservative setting, not a measured limit.
- **Quota:** every reply includes `usage.remaining_limits`; the meaning is
  unverified.
- **Backend:** Proton does not name the backend models.

`ai-policy` denies Lumo (`vendor:lumo`, `service:lumo-gateway`) in ZenithFlow
repositories; ZenithFlow uses its own local models.

## How the tool-calling harness works

Claude sends Anthropic Messages to a temporary LiteLLM listener. LiteLLM maps
text, tool definitions, tool calls, results, and streaming events to an
OpenAI-compatible chat-completions interface. A second local listener forwards
to the configured chat gateway and converts its double-encoded non-streaming
JSON into an object; server-sent event streams pass through. Both listeners
bind to `127.0.0.1`, use independently generated per-launch authentication
tokens, and normally stop when Claude exits. The upstream key is held by the
bridge and is not sent to LiteLLM or included in command arguments. The bridge
does not log prompts or credentials. If the launcher is forcibly killed, check
for and stop an orphaned local LiteLLM process.

Normal Claude Code permissions apply. Inherited Anthropic routing and OAuth
variables are removed in the child; the parent shell's settings are not
changed. All model tier defaults and the default subagent model are set to the
selected gateway ID, but a custom agent can explicitly request a different
model, which this one-model gateway will reject. Background or detached sessions
cannot be assumed to outlive the launcher and its temporary gateway.

The chat server is an external connection, so prompts, file contents that Claude
reads, tool results, and tool schemas may leave this computer and reach that
server and its upstream provider. This path is not Pangolin or a verified
on-premises model. Do not assume Proton's privacy promises apply to an
independently operated gateway. The launcher does not perform an automatic
provider or model fallback; the upstream service's own routing is not verified.
Errors, rate limits, and timeouts are returned to Claude. The service may impose
usage limits shared with other consumers, including the Signal bot.

## Verification and limits

Tested 2026-10-30 with Claude Code 2.1.308, LiteLLM 1.102.1 and `lumo-lite`:

- An authenticated gateway request produced a structured tool call, and a
  second turn interpreted the returned result correctly.
- Claude Code used `Read` to return an exact marker from a disposable file.
- In a separate disposable directory, Claude used Read, Edit and Bash to fix a
  small arithmetic bug. Its first edit used a nonexistent path; it inspected the
  directory, retried, and the unchanged tests passed when run independently.
- After the server update, a disposable multi-step task with approximately
  161–163 KB requests read two files, fixed two arithmetic bugs, ran the
  unchanged tests and finished without a continuation prompt. The tests also
  passed when run independently.
- Local regression tests check authorization, JSON normalization, streaming,
  error redaction, and fail-closed model selection. Run them with:

  ```sh
  "$HOME/.local/share/claude-lumo/venv/bin/python" -m unittest scripts/test_claude_lumo.py
  ```

On 2026-10-30 the `lumo-max` ID was absent and returned `Model not found` for
this key. By 2026-11-14 it was listed and answered tool calls through Hermes and
OpenCode. Its actual backend and inference quality are not verified. Proton lists GLM 5.3 among Lumo's models but does not establish the
backend used by this gateway's `lumo-max` alias. Long sessions, compaction,
parallel subagents, MCP servers, image input, cancellation during streaming,
and concurrent sessions remain unqualified. The successful tests do not make
this suitable for unattended protected repository changes without independent
review and checks.

### Large requests and the former upstream HTTP 500

On 2026-10-30, the gateway returned HTTP 500 for an ordinary full-tool Claude
request of about 163 KB. Synthetic requests of 99,936 bytes succeeded while
100,136 bytes failed. The upstream Lumo proxy's error reports an
`AttributeError` reading `getvalue()` from a `BufferedRandom` request body.
This is an upstream byte limit, not the model's token context window. Claude's
“unrecognized model, 200k assumed” warning does not measure this limit.

After the server-side update, synthetic requests of 104,475, 172,299 and
208,827 bytes all returned successful completions. The largest reported 46,934
prompt tokens. A Claude Code documentation task in `~/Git/IrregularChat` then
completed with the full tool set, using four tool calls and requests up to
182,628 bytes. The former 99,000-byte local guard has been removed. The bridge
still enforces a 32 MiB defensive request-body limit and does not truncate
prompts or tool results. It recognizes the previous upstream buffer error if
it recurs and reports it without repeated retries.

The model's actual context window and whether 200,000 tokens are supported
remain unverified; byte counts are not token counts. Automatic compaction,
long conversations and downstream model routing remain unqualified. Existing
Claude sessions must be restarted to pick up the bridge changes.

## References

- [Claude Code gateway configuration](https://code.claude.com/docs/en/llm-gateway-connect)
- [LiteLLM client setup and compatibility](https://docs.litellm.ai/docs/proxy/client_setup/overview)
- [LiteLLM's OpenAI-compatible endpoint routing](https://docs.litellm.ai/docs/response_api_native_passthrough)
- [Proton's Lumo model and reasoning modes](https://proton.me/support/lumo-models)
- [Proton's description of Lumo model hosting](https://proton.me/support/lumo-privacy)
