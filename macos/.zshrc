export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
alias age_pub='/private/tmp/age-py/age.sh'
# ~/.zshrc
# Set GPG TTY
export GPG_TTY=$(tty)
# Set the default gpg program
git config --global gpg.program $(which gpg)

# Set the default prompt
export PS1="%n@%m %1~ %# "

# # Enable command auto-suggestions
# autoload -U compinit && compinit

# Load zsh configuration files
for config_file in ~/.zsh_{aliases,aws,functions,developer,apps,network,transfer,security,utils,docker,handle_files,encryption,git,linux_compat}; do
  if [ -f "$config_file" ]; then
    source "$config_file"
  fi
done

# Define OS 
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$NAME
elif type lsb_release &> /dev/null; then
  OS=$(lsb_release -si)
else
  OS=$(uname -s)
fi


# Enable syntax highlighting if installed
if [ -f /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
  source /usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Load the Zsh history file
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# ----------------------
# Applications
# ----------------------
# check if brew is installed and install it if not

# ----------------------
# Enhanced Prompt with Git Branch and Time
# ----------------------
# autoload -Uz vcs_info
# precmd() { vcs_info }
# zstyle ':vcs_info:*' formats '(%b)'

# export PS1="%n@%m %1~ [%D{%L:%M:%S}] ${vcs_info_msg_0_} %# "

# Function to enable Touch ID for sudo
sudotouch() {
  # Check if Touch ID is already enabled for sudo
  if grep -q "auth       sufficient     pam_tid.so" /etc/pam.d/sudo; then
    echo "Touch ID for sudo is already enabled."
    return
  fi

  # Prompt to enable Touch ID for sudo
  REPLY="n" # default to no
  echo -n "Touch ID for sudo is not enabled. Do you want to enable it for Macs with Touch Bar? (y/n):(default:n) "
  read REPLY
  REPLY=${REPLY:-n}
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo sed -i '' '1s;^;auth       sufficient     pam_tid.so\n;' /etc/pam.d/sudo
    echo "Touch ID for sudo has been enabled."
  else 
    echo "Touch ID for sudo not enabled. Passwords will be required for sudo."
  fi
}
# alias for initial-setup.sh
alias initial-install="./initial_macos_setup.sh"
# call sudotouch to enable Touch ID for sudo if not already enabled
sudotouch

# Add local bin to PATH
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

# Source environment variables (secrets kept out of shell config)
if [ -f "$HOME/.env" ]; then
  set -a
  source "$HOME/.env"
  set +a
fi

. "$HOME/.local/bin/env"

# ── Claude Code Backend Switching ─────────────────────────────────────────────
# Switch between Anthropic Cloud and self-hosted/Vibe backends
alias claude-cloud='source claude-switch cloud'
alias claude-local='source claude-switch local'
alias claude-ollama='source claude-switch ollama'
alias claude-vibe='source claude-switch vibe'
alias claude-status='source claude-switch status'

# ── Claude Code launchers ─────────────────────────────────────────────────────
# Naming convention (2026-06-06 cleanup):
#   cc / cc-cloud             → Anthropic cloud (Opus/Sonnet)
#   cc-mac / cc-local         → this Mac (vanilla Ollama → qwen3-coder)
#   cc-vibe                   → Mistral via local LiteLLM proxy (default: mistral-medium)
#   cc-vibe-thinking          →   mistral-large 3 (heavy reasoning, planning)
#   cc-vibe-fast              →   devstral-small (cheap fanout)
#   cc-vibe-reason            →   magistral-medium (architecture decisions)
#   cc-obelisk                → Mistral Medium 3.5 on the Obelisk B200s (remote, was cc-local)
#   MODEL=<name> cc-vibe      → any model registered in ~/.vibe/litellm-config.yaml
#
# Bare `cc` explicitly switches to cloud first so it doesn't inherit a stale
# ANTHROPIC_BASE_URL from a prior cc-vibe / cc-mac session in the same shell.
alias cc='source claude-switch cloud && claude --dangerously-skip-permissions --teammate-mode auto'
alias cc-cloud='source claude-switch cloud && claude --dangerously-skip-permissions --teammate-mode auto'

# ── Mistral-backed Claude Code (cc-vibe family + cc-obelisk) ─────────────────
# Mistral models default to "presentation mode" (printing commands rather than
# executing them). The vibe-execute.md prompt fragment overrides that posture
# via --append-system-prompt. If the file is missing, the function still works
# — just without the nudge.
_cc_mistral() {
  local backend="$1"; shift
  source claude-switch "$backend"
  local prompt_file="$HOME/.claude/prompts/vibe-execute.md"
  local -a extra=()
  [ -r "$prompt_file" ] && extra=(--append-system-prompt "$(cat "$prompt_file")")
  [ -n "${CLAUDE_BARE:-}" ] && extra+=(--bare)
  # --strict-mcp-config + empty inline config: same Anthropic-cloud MCP fetch
  # hang that bit cc-mac applies to any non-Anthropic backend. See cc-mac
  # comment below for context (anthropics/claude-code#25412).
  # --exclude-dynamic-system-prompt-sections: moves cwd/env/git-status out of
  # the system prompt so the prompt cache survives `cd` changes.
  if [ -n "${MODEL:-}" ]; then
    ANTHROPIC_MODEL="$MODEL" \
    ANTHROPIC_CUSTOM_MODEL_OPTION="$MODEL" \
    ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="${MODEL_NAME:-$MODEL}" \
      claude --dangerously-skip-permissions --teammate-mode auto \
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
        --exclude-dynamic-system-prompt-sections \
        "${extra[@]}" "$@"
  else
    claude --dangerously-skip-permissions --teammate-mode auto \
      --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
      --exclude-dynamic-system-prompt-sections \
      "${extra[@]}" "$@"
  fi
}

# Obelisk B200 cluster (formerly named "cc-local" — name was misleading
# because the endpoint is remote, just not Anthropic). Currently routed
# through ai.digitalfacility.io/api → LiteLLM gateway → Mistral Medium 3.5.
alias cc-obelisk='_cc_mistral local'

# Local LiteLLM proxy at 127.0.0.1:4000 → official Mistral API. Default
# mistral-medium. Variants below set MODEL per call.
alias cc-vibe='_cc_mistral vibe'
alias cc-vibe-thinking='MODEL=mistral-large MODEL_NAME="Mistral Large 3" _cc_mistral vibe'
alias cc-vibe-fast='MODEL=devstral-small MODEL_NAME="Devstral Small" _cc_mistral vibe'
alias cc-vibe-reason='MODEL=magistral-medium MODEL_NAME="Magistral Medium" _cc_mistral vibe'
# Compatibility alias — cc-vibe-think was the original name; kept so existing
# muscle memory and scripts don't break.
alias cc-vibe-think='cc-vibe-thinking'

# cc-mac — Claude Code against local Ollama.
# Status (2026-06-05 07:00, working): cc-mac = vanilla Ollama Anthropic-compat
# → qwen3-coder-next-cc:128k. cc-mac-proxy = legacy patched-proxy path.
# cc-mac-gemma = gemma multimodal via proxy Haiku tier.
# See ~/Git/llms-local/docs/cc-mac-design.md for the full story.
#
# Performance: prompt eval on M4 Max is ~400 tok/s with 80B-A3B MoE. Claude
# Code sends ~130K tokens of system prompt → 5+ min before the first
# generated token. AVOID `/team-*` and `/gsd:*` skills on cc-mac — they
# spawn subagents that each pay the prompt-eval cost again.
#
# Aliases:
#   cc-mac        → qwen3-coder-next-cc:128k  (best quality, slow eval)
#   cc-mac-fast   → qwen3-coder-next-cc:32k   (faster eval, smaller context)
#   cc-mac-proxy  → qwen3-coder-cc:128k via patched proxy (fallback)
#   cc-mac-gemma  → gemma4-cc:128k via proxy SMALL tier (multimodal, weak at code)
_cc_ollama() {
  local backend="${1:-ollama-proxy}"; shift 2>/dev/null
  source claude-switch "$backend"
  # Optional per-invocation model override (used by cc-mac-fast)
  if [ -n "${OLLAMA_MODEL_OVERRIDE:-}" ]; then
    export ANTHROPIC_MODEL="$OLLAMA_MODEL_OVERRIDE"
    export ANTHROPIC_CUSTOM_MODEL_OPTION="$OLLAMA_MODEL_OVERRIDE"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$OLLAMA_MODEL_OVERRIDE"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$OLLAMA_MODEL_OVERRIDE"
    echo "  Override: ANTHROPIC_MODEL=$OLLAMA_MODEL_OVERRIDE"
  fi
  local prompt_file="$HOME/.claude/prompts/vibe-execute.md"
  local -a extra=()
  [ -r "$prompt_file" ] && extra=(--append-system-prompt "$(cat "$prompt_file")")
  [ -n "${CLAUDE_BARE:-}" ] && extra+=(--bare)
  # Prevent Claude Code from hanging on Anthropic-cloud MCP-config fetch when
  # using a local backend. See anthropics/claude-code#25412. `--strict-mcp-config`
  # + empty inline config tells it: "these are the MCP servers, period — don't
  # phone home for more." Critical for cc-mac usability; without it sessions
  # hang for 7+ minutes on startup with only 3 tokens transmitted.
  # --exclude-dynamic-system-prompt-sections: lets prompt cache survive cd.
  # --tools: trim system prompt — local 80B-A3B uses these 95% of the time;
  #   skips the rest of the palette (~10-15% prompt shrinkage). Add Skill if
  #   you want /skill-name resolution.
  claude --dangerously-skip-permissions --teammate-mode auto \
    --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
    --exclude-dynamic-system-prompt-sections \
    --tools "Read,Edit,Write,Bash,Grep,Glob,Agent" \
    "${extra[@]}" "$@"
}

alias cc-mac='_cc_ollama ollama'              # vanilla Ollama → qwen3-coder-next-cc:128k (no proxy)
alias cc-local='cc-mac'                       # synonym — "local" now means literally on this Mac
alias cc-mac-fast='OLLAMA_MODEL_OVERRIDE=qwen3-coder-next-cc:32k _cc_ollama ollama'  # 32K ctx — much faster prompt-eval
alias cc-mac-proxy='_cc_ollama ollama-proxy'  # legacy path: qwen3-coder-cc:128k via patched proxy
alias cc-mac-gemma='_cc_ollama ollama-proxy-gemma'  # gemma4-cc:128k via proxy SMALL_MODEL tier

# --bare variants — skip hooks, auto-memory, plugin sync, CLAUDE.md
# auto-discovery, background prefetches, keychain reads. On cc-mac this is
# the difference between "5+ min to first token" and ~30s. Tradeoff: no
# auto-memory, no global CLAUDE.md, no skill auto-resolution from settings.
# Right for scripted fanout / quick one-shots, not the daily driver.
# Skills still resolve when you type `/name` explicitly.
alias cc-vibe-bare='CLAUDE_BARE=1 _cc_mistral vibe'
alias cc-mac-bare='CLAUDE_BARE=1 _cc_ollama ollama'
