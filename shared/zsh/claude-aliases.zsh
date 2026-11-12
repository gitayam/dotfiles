# claude-aliases.zsh — Claude Code launchers. Sourced from ~/.zshrc (and ~/.bashrc).
#
# Claude Code is the only harness. It runs against one of three backends:
#
#   cc            Anthropic cloud (clears any self-hosted settings first)
#   cc1           server 1: GLM-5.3-Flash, 262K context         (claude-z 1)
#   cc2           server 2: gpt-oss-120b, 49K context           (claude-z 2)
#   ccm <key>     any other chat model in shared/llm/models.conf with a 40K+
#                 window (the 32K Qwen models are for zq only)
#   ccz           first reachable server (1, then 2), else local Ollama
#   cc-status     every model on both servers: up or down, port, window
#
# Without Claude Code, any model on either server (chat, translate, embed):
#   zq <key> "prompt"   (zq --help; keys: 1 2 2q 2s 2f 2t 2e, or glm, qwen, ...)
#
# The cc* launchers add the flags below. `claude`, `z1`, `z2`, `z2q` and `zl`
# are the same backends without them. Self-hosted launches go through
# claude-z, which starts the SSH tunnel and sets the model, tier and context
# variables for that one process, so nothing leaks into this shell.

_CC_FLAGS=(--dangerously-skip-permissions --teammate-mode auto)

# For anyone still sourcing claude-switch by hand (synced via ~/.vibe)
export CLAUDE_BACKENDS_CONFIG="${CLAUDE_BACKENDS_CONFIG:-$HOME/.vibe/claude-backends.env}"

# Variables a self-hosted backend sets; cloud runs must not inherit them
_CC_SELFHOSTED_VARS=(
  ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL
  ANTHROPIC_CUSTOM_MODEL_OPTION ANTHROPIC_CUSTOM_MODEL_OPTION_NAME
  ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
  ANTHROPIC_SMALL_FAST_MODEL CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS
  CLAUDE_CODE_MAX_CONTEXT_TOKENS CLAUDE_CODE_AUTO_COMPACT_WINDOW
  CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT CLAUDE_CODE_MAX_OUTPUT_TOKENS
)

# Older versions of this file defined these as aliases; a function can't be
# defined over a live alias, so re-sourcing would fail without this
unalias cc cc-cloud cc1 cc2 cc2q ccz ccm cc-status claude-cloud claude-status \
  claude-local claude-ollama claude-vibe claude-deepseek cc-local cc-vibe \
  cc-vibe-think cc-vibe-fast cc-vibe-reason cc-deepseek cc-deepseek-pro 2>/dev/null

cc() {
  local v; local -a unset_args=()
  for v in "${_CC_SELFHOSTED_VARS[@]}"; do unset_args+=(-u "$v"); done
  env "${unset_args[@]}" claude "${_CC_FLAGS[@]}" "$@"
}
cc-cloud() { cc "$@"; }

cc1()  { claude-z 1 "${_CC_FLAGS[@]}" "$@"; }
cc2()  { claude-z 2 "${_CC_FLAGS[@]}" "$@"; }
ccz()  { claude-z "${_CC_FLAGS[@]}" "$@"; }
ccm()  { local k="${1:?usage: ccm <model key>}"; shift; claude-z "$k" "${_CC_FLAGS[@]}" "$@"; }

cc-status() {
  claude-z status
  if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
    echo "note: this shell has ANTHROPIC_BASE_URL=$ANTHROPIC_BASE_URL; plain \`claude\` uses it. Run claude-cloud to clear it."
  fi
}

# Clear self-hosted settings from this shell (left by an old `source claude-switch`)
claude-cloud() {
  local v
  for v in "${_CC_SELFHOSTED_VARS[@]}"; do unset "$v"; done
  echo "This shell now uses Anthropic cloud."
}
