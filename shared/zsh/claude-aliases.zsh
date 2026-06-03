# claude-aliases.zsh — Claude Code backend switching + cc-* aliases
# Sourced from ~/.zshrc on every device. Requires `claude-switch` in PATH.
#
# Install: in ~/.zshrc, add (idempotent guard already used in setup script):
#   [ -r "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh" ] && \
#     source "$HOME/Git/dotfiles/shared/zsh/claude-aliases.zsh"

# Backend config lives in ~/.vibe/ (synced via vibe-config Syncthing folder)
# so that LOCAL_AUTH_TOKEN propagates across devices.
export CLAUDE_BACKENDS_CONFIG="${CLAUDE_BACKENDS_CONFIG:-$HOME/.vibe/claude-backends.env}"

alias claude-cloud='source claude-switch cloud'
alias claude-local='source claude-switch local'
alias claude-ollama='source claude-switch ollama'
alias claude-vibe='source claude-switch vibe'
alias claude-status='source claude-switch status'
alias cc='claude --dangerously-skip-permissions --teammate-mode auto'
alias cc-cloud='source claude-switch cloud && claude --dangerously-skip-permissions --teammate-mode auto'

_cc_mistral() {
  local backend="$1"; shift
  source claude-switch "$backend"
  local prompt_file="$HOME/.claude/prompts/vibe-execute.md"
  local -a extra=()
  [ -r "$prompt_file" ] && extra=(--append-system-prompt "$(cat "$prompt_file")")
  if [ -n "${MODEL:-}" ]; then
    ANTHROPIC_MODEL="$MODEL" \
    ANTHROPIC_CUSTOM_MODEL_OPTION="$MODEL" \
    ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="${MODEL_NAME:-$MODEL}" \
      claude --dangerously-skip-permissions --teammate-mode auto "${extra[@]}" "$@"
  else
    claude --dangerously-skip-permissions --teammate-mode auto "${extra[@]}" "$@"
  fi
}

alias cc-local='_cc_mistral local'
alias cc-vibe='_cc_mistral vibe'
alias cc-vibe-think='MODEL=mistral-large MODEL_NAME="Mistral Large 3" _cc_mistral vibe'
alias cc-vibe-fast='MODEL=devstral-small MODEL_NAME="Devstral Small" _cc_mistral vibe'
alias cc-vibe-reason='MODEL=magistral-medium MODEL_NAME="Magistral Medium" _cc_mistral vibe'
