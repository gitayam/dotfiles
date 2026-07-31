#!/usr/bin/env bash
# Detect Docker/containerd split-brain and verify that every Signal ingress
# path reaches the same process. General runtime drift is alert-only. Optional
# Signal repair is deliberately narrow and requires an exact process fingerprint.

set -uo pipefail

# shellcheck source=/dev/null
[ -r /etc/docker-stack-recovery.conf ] && source /etc/docker-stack-recovery.conf

NTFY_URL="${NTFY_URL:-http://127.0.0.1:2586}"
NTFY_TOPIC="${NTFY_TOPIC:-proxmox-recovery}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
SIGNAL_AUTOHEAL="${SIGNAL_AUTOHEAL:-false}"
SIGNAL_CONTAINER="signal-bot-selfhosted-signal-bot-1"
SIGNAL_COMPOSE_DIR="/datadrive/home/signal-bot-selfhosted"
SIGNAL_PUBLIC_URL="https://signal.irregulars.io/health"
# Cross-post alerts into the same Bot Dev Signal room the in-app daemon
# watchdog uses (SignalBot.notifyDaemonRestart), so host- and app-level
# incidents land in one place. Best-effort only: SIGNAL_BOT_API_KEY must be
# set explicitly in /etc/docker-stack-recovery.conf (mirroring NTFY_TOKEN) --
# there is no safe default for a credential. Sends routinely no-op during the
# exact "bot.running: false" incidents this script exists to catch (the
# endpoint returns 503 when the bot isn't running) -- that's expected, not a
# bug; ntfy remains the channel of record for anything Signal itself can't
# deliver. See docs/runbooks/docker-runtime-split-brain.md.
SIGNAL_BOT_API_KEY="${SIGNAL_BOT_API_KEY:-}"
SIGNAL_BOT_DEV_GROUP_ID="${SIGNAL_BOT_DEV_GROUP_ID:-6PP/i0JBlXpAe+dkxvH64ZKmOQoeaukKtsPUQU5wQTg=}"
SIGNAL_RESTART_FAILURE_LOG="${SIGNAL_COMPOSE_DIR}/signal-data/daemon-restart-failures.log"
STATE_DIR="/var/lib/docker-runtime-monitor"
NOTIFY_REPEAT_SECONDS=3600
AUTOHEAL_COOLDOWN_SECONDS=900
LOG_TAG="docker-runtime-monitor"

# --- AI last-resort diagnosis (SHADOW MODE ONLY) ---
# Fires only when the SAME issue has persisted well past what deterministic
# autoheal can be expected to fix (2+ cooldown windows) and its own separate
# rate limit allows it. It NEVER executes anything -- there is no code path in
# this script that runs a command chosen by the model. It only produces a
# richer diagnosis + a "here's what I would have done" recommendation, logged
# to $STATE_DIR/ai-incidents/ and sent via notify(). Arming real execution is
# a deliberately separate, not-yet-built decision -- see
# docs/runbooks/docker-runtime-split-brain.md before ever adding one.
AI_LAST_RESORT_ENABLED="${AI_LAST_RESORT_ENABLED:-false}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
AI_LAST_RESORT_MODEL="${AI_LAST_RESORT_MODEL:-gpt-5.4-mini}"
AI_LAST_RESORT_THRESHOLD_SECONDS=1800  # ~2 autoheal cooldowns
AI_LAST_RESORT_COOLDOWN_SECONDS=3600   # at most 1 AI call/hour
AI_LAST_RESORT_DAILY_CAP=5             # hard stop regardless of cooldown math

mkdir -p "$STATE_DIR"
exec 9>"/run/lock/docker-runtime-monitor.lock"
if ! flock -n 9; then
  echo "[$LOG_TAG] another monitor run is active"
  exit 0
fi

work_dir=$(mktemp -d /tmp/docker-runtime-monitor.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

log() { echo "[$LOG_TAG] $*"; }

notify_signal() {
  local text="$1"
  [ -n "$SIGNAL_BOT_API_KEY" ] || return 0
  local payload
  payload=$(jq -n --arg gid "$SIGNAL_BOT_DEV_GROUP_ID" --arg msg "$text" \
    '{groupId: $gid, message: $msg}')
  curl -sf -m 10 -X POST "http://127.0.0.1:8082/bot/send" \
    -H "Content-Type: application/json" \
    -H "X-Bot-API-Key: ${SIGNAL_BOT_API_KEY}" \
    -d "$payload" >/dev/null 2>&1 || true
}

notify() {
  local title="$1" message="$2" priority="${3:-default}"
  local headers=(-H "Title: ${title}" -H "Priority: ${priority}")
  if [ -n "$NTFY_TOKEN" ]; then
    headers+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
  fi
  curl -sf -m 10 -X POST "${NTFY_URL}/${NTFY_TOPIC}" \
    "${headers[@]}" -d "$message" >/dev/null 2>&1 || log "ntfy post failed (non-fatal)"
  notify_signal "🖥️ [host] ${title}: ${message}"
}

is_ready() {
  jq -e '.status == "healthy" and .database == "connected" and .bot.running == true' \
    >/dev/null 2>&1 <<<"$1"
}

json_instance_id() {
  jq -r '.instance_id // empty' <<<"$1" 2>/dev/null
}

is_signal_task() {
  local id="$1" info image args signal_mount
  info=$(ctr -n moby containers info "$id" 2>/dev/null || true)
  image=$(jq -r '.Image // ""' <<<"$info")
  args=$(jq -r '.Spec.process.args // [] | join(" ")' <<<"$info")
  signal_mount=$(jq -r \
    '[.Spec.mounts[]? | select(.destination == "/app/signal-data" and .source == "/datadrive/home/signal-bot-selfhosted/signal-data")] | length' \
    <<<"$info")
  [ "$image" = "docker.io/library/signal-bot-selfhosted-signal-bot:latest" ] \
    && [[ "$args" == *"node dist/index-selfhosted.js"* ]] \
    && [ "$signal_mount" = "1" ]
}

declare -a issues signal_orphans
running_unmanaged_count=0
internal_json=""
published_json=""
public_json=""
internal_id=""
published_id=""
public_id=""
internal_ready=0

audit_runtime() {
  issues=()
  signal_orphans=()
  running_unmanaged_count=0

  if ! mountpoint -q /datadrive; then
    issues+=("/datadrive is not mounted")
    return
  fi
  if ! docker info >/dev/null 2>&1; then
    issues+=("Docker daemon is unavailable")
    return
  fi

  docker ps -aq --no-trunc | sort >"$work_dir/docker.ids"
  ctr -n moby tasks list -q | sort >"$work_dir/tasks.ids"
  comm -13 "$work_dir/docker.ids" "$work_dir/tasks.ids" >"$work_dir/unmanaged.ids"

  while IFS= read -r id; do
    [ -z "$id" ] && continue
    state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
    [ "$state" = "RUNNING" ] || continue
    running_unmanaged_count=$((running_unmanaged_count + 1))
    if is_signal_task "$id"; then
      signal_orphans+=("$id")
    fi
  done <"$work_dir/unmanaged.ids"

  if [ "$running_unmanaged_count" -gt 0 ]; then
    issues+=("${running_unmanaged_count} running containerd task(s) are outside Docker control")
  fi

  internal_json=$(docker exec "$SIGNAL_CONTAINER" \
    curl -fsS --max-time 10 http://127.0.0.1:8080/health 2>/dev/null || true)
  published_json=$(curl -fsS --max-time 10 http://127.0.0.1:8082/health 2>/dev/null || true)
  public_json=$(curl -fsS --max-time 10 "$SIGNAL_PUBLIC_URL" 2>/dev/null || true)
  internal_id=$(json_instance_id "$internal_json")
  published_id=$(json_instance_id "$published_json")
  public_id=$(json_instance_id "$public_json")
  internal_ready=0

  if is_ready "$internal_json"; then
    internal_ready=1
  else
    issues+=("Signal container-local readiness failed")
  fi
  if ! is_ready "$published_json"; then
    issues+=("Signal host-published readiness failed")
  fi
  if ! is_ready "$public_json"; then
    issues+=("Signal public readiness failed")
  fi

  if [ -z "$internal_id" ] || [ -z "$published_id" ] || [ -z "$public_id" ]; then
    issues+=("Signal instance identity is missing on one or more paths")
  elif [ "$internal_id" != "$published_id" ] || [ "$internal_id" != "$public_id" ]; then
    issues+=("Signal identity mismatch: internal=${internal_id} published=${published_id} public=${public_id}")
  fi
}

autoheal_on_cooldown() {
  local now last=0
  now=$(date +%s)
  if [ -r "$STATE_DIR/last-autoheal" ]; then
    read -r last <"$STATE_DIR/last-autoheal"
  fi
  [ $((now - last)) -lt "$AUTOHEAL_COOLDOWN_SECONDS" ]
}

mark_autoheal() {
  date +%s >"$STATE_DIR/last-autoheal"
}

stop_exact_signal_orphan() {
  local id="$1"
  if ! is_signal_task "$id"; then
    log "refusing orphan cleanup because fingerprint changed: $id"
    return 1
  fi

  log "terminating exact-fingerprint unmanaged Signal task $id"
  ctr -n moby tasks kill --signal SIGTERM "$id" >/dev/null 2>&1 || true
  for _ in $(seq 1 10); do
    state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
    [ "$state" != "RUNNING" ] && break
    sleep 1
  done
  state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
  if [ "$state" = "RUNNING" ]; then
    ctr -n moby tasks kill --signal SIGKILL "$id" >/dev/null 2>&1 || return 1
    sleep 1
  fi
  ctr -n moby tasks delete "$id" >/dev/null 2>&1 || true
  ctr -n moby containers delete "$id" >/dev/null 2>&1 || true
}

maybe_autoheal_signal() {
  [ "$SIGNAL_AUTOHEAL" = "true" ] || return 1
  autoheal_on_cooldown && return 1

  # Never touch a broad split-brain event. The only automatic orphan cleanup
  # allowed is one exact Signal task and no other unmanaged running process.
  if [ "$running_unmanaged_count" -eq 1 ] \
    && [ "${#signal_orphans[@]}" -eq 1 ] \
    && [ "$internal_ready" -eq 1 ]; then
    mark_autoheal
    stop_exact_signal_orphan "${signal_orphans[0]}" || return 1
    (cd "$SIGNAL_COMPOSE_DIR" && docker compose up -d --force-recreate signal-bot) || return 1
    notify "Signal split-brain auto-heal attempted" \
      "Removed one exact-fingerprint unmanaged Signal task and recreated the canonical service." "high"
    sleep 10
    return 0
  fi

  # If Docker has full runtime control but the canonical service itself is not
  # ready, permit one rate-limited narrow compose recovery. `up -d` alone is a
  # no-op here: Compose only recreates on a config/image diff, and a process
  # that's alive-but-internally-broken (e.g. a dead signal-cli daemon inside a
  # still-running Node process) looks unchanged to Compose. --force-recreate
  # is required to actually restart it (2026-07-28 outage: this branch fired
  # every 15 minutes for the full outage and never once worked).
  if [ "$running_unmanaged_count" -eq 0 ] && [ "$internal_ready" -eq 0 ]; then
    mark_autoheal
    (cd "$SIGNAL_COMPOSE_DIR" && docker compose up -d --force-recreate signal-bot) || return 1
    notify "Signal readiness auto-heal attempted" \
      "No runtime split-brain was present; force-recreated the canonical Signal stack." "high"
    sleep 10
    return 0
  fi

  return 1
}

report_state() {
  local summary fingerprint previous="" last_notify=0 now
  now=$(date +%s)

  if [ "${#issues[@]}" -eq 0 ]; then
    summary="healthy instance=${internal_id}"
    if [ -r "$STATE_DIR/fingerprint" ]; then
      read -r previous <"$STATE_DIR/fingerprint"
    fi
    if [ -n "$previous" ] && [ "$previous" != "healthy" ]; then
      notify "Docker runtime and Signal routing recovered" "$summary" "default"
    fi
    printf 'healthy\n' >"$STATE_DIR/fingerprint"
    printf '%s\n' "$summary" >"$STATE_DIR/summary"
    rm -f "$STATE_DIR/fingerprint-first-seen"
    log "$summary"
    return 0
  fi

  summary=$(printf '%s; ' "${issues[@]}")
  fingerprint=$(printf '%s' "$summary" | sha256sum | awk '{ print $1 }')
  [ -r "$STATE_DIR/fingerprint" ] && read -r previous <"$STATE_DIR/fingerprint"
  [ -r "$STATE_DIR/last-notify" ] && read -r last_notify <"$STATE_DIR/last-notify"

  log "UNHEALTHY: $summary"
  if [ "$fingerprint" != "$previous" ] || [ $((now - last_notify)) -ge "$NOTIFY_REPEAT_SECONDS" ]; then
    notify "Docker runtime or Signal routing unhealthy" "$summary" "urgent"
    printf '%s\n' "$now" >"$STATE_DIR/last-notify"
  fi
  if [ "$fingerprint" != "$previous" ]; then
    printf '%s\n' "$now" >"$STATE_DIR/fingerprint-first-seen"
  fi
  printf '%s\n' "$fingerprint" >"$STATE_DIR/fingerprint"
  printf '%s\n' "$summary" >"$STATE_DIR/summary"
  return 1
}

# Best-effort redaction before anything leaves the host for a third-party API.
# Not a substitute for keeping secrets out of logs in the first place -- a
# defense-in-depth pass over auth headers, bearer tokens, and common
# key/password value patterns.
sanitize_for_ai() {
  # All patterns rely on the trailing /i flag for case-insensitivity (GNU sed
  # 4.9, confirmed on proxmox-main) rather than partial [Xx]-style character
  # classes, which only covered single letters and silently missed e.g.
  # "X-Bot-API-Key" (all-caps API) and "DB_PASSWORD" (all-caps PASSWORD).
  sed -E \
    -e 's/(authorization:?["'"'"' ]*bearer)[[:space:]]+[A-Za-z0-9._-]+/\1 [REDACTED]/gi' \
    -e 's/(x-(bot-)?api-key:?["'"'"' ]*)[A-Za-z0-9._-]{6,}/\1[REDACTED]/gi' \
    -e 's/(api[_-]?key["'"'"': =]+)[A-Za-z0-9._-]{6,}/\1[REDACTED]/gi' \
    -e 's/(password["'"'"': =]+)[^ ,"'"'"']+/\1[REDACTED]/gi' \
    -e 's/(sk-[A-Za-z0-9]{10,})/[REDACTED]/g'
}

ai_daily_count() {
  local today count=0
  today=$(date +%Y-%m-%d)
  [ -r "$STATE_DIR/ai-daily-count" ] || { echo 0; return; }
  read -r day count <"$STATE_DIR/ai-daily-count" 2>/dev/null || true
  [ "$day" = "$today" ] && echo "${count:-0}" || echo 0
}

ai_mark_invocation() {
  local today
  today=$(date +%Y-%m-%d)
  local count
  count=$(ai_daily_count)
  printf '%s %s\n' "$today" "$((count + 1))" >"$STATE_DIR/ai-daily-count"
  date +%s >"$STATE_DIR/ai-last-invocation"
}

maybe_ai_last_resort() {
  [ "$AI_LAST_RESORT_ENABLED" = "true" ] || return 0
  [ -n "$OPENAI_API_KEY" ] || return 0
  [ "${#issues[@]}" -gt 0 ] || return 0 # nothing to diagnose

  local first_seen now
  now=$(date +%s)
  [ -r "$STATE_DIR/fingerprint-first-seen" ] || return 0
  read -r first_seen <"$STATE_DIR/fingerprint-first-seen"
  [ $((now - first_seen)) -ge "$AI_LAST_RESORT_THRESHOLD_SECONDS" ] || return 0

  local last_run=0
  [ -r "$STATE_DIR/ai-last-invocation" ] && read -r last_run <"$STATE_DIR/ai-last-invocation"
  [ $((now - last_run)) -ge "$AI_LAST_RESORT_COOLDOWN_SECONDS" ] || return 0
  [ "$(ai_daily_count)" -lt "$AI_LAST_RESORT_DAILY_CAP" ] || {
    log "AI last-resort: daily cap reached, skipping"
    return 0
  }

  log "AI last-resort: issue persisted $((now - first_seen))s, invoking diagnosis (SHADOW MODE)"
  ai_mark_invocation

  local docker_state disk_state mem_state log_tail bundle system_prompt payload response content
  docker_state=$(docker ps -a --filter name=signal-bot --format '{{.Names}} {{.Status}}' 2>&1 | sanitize_for_ai)
  disk_state=$(df -h /datadrive 2>&1 | sanitize_for_ai)
  mem_state=$(free -h 2>&1 | sanitize_for_ai)
  log_tail=$(docker logs "$SIGNAL_CONTAINER" --tail 150 2>&1 | sanitize_for_ai | tail -c 8000)

  bundle=$(jq -n \
    --arg issues "$(printf '%s; ' "${issues[@]}")" \
    --arg persisted "$((now - first_seen))" \
    --arg docker_state "$docker_state" \
    --arg disk_state "$disk_state" \
    --arg mem_state "$mem_state" \
    --arg log_tail "$log_tail" \
    --arg internal "$internal_json" \
    --arg published "$published_json" \
    --arg public "$public_json" \
    '{issues:$issues, seconds_persisted:$persisted, docker_ps:$docker_state, disk:$disk_state, memory:$mem_state, recent_log_tail:$log_tail, health_internal:$internal, health_published:$published, health_public:$public}')

  system_prompt='You are a last-resort diagnostic assistant for the IrregularChat Signal bot on proxmox-main. Deterministic autoheal (docker compose up -d --force-recreate signal-bot / restart postgres or redis) has already been tried and the issue persists. You are running in SHADOW MODE: your recommended_action is NEVER executed automatically, it is only logged and shown to a human. Respond with ONLY a JSON object: {"diagnosis": "short human-readable diagnosis", "confidence": "low|medium|high", "recommended_action": one of ["RESTART_SIGNAL_BOT_FORCE_RECREATE","RESTART_POSTGRES","RESTART_REDIS","NO_SAFE_ACTION_ESCALATE_HUMAN"], "reasoning": "why"}. If you are not confident the issue matches a known pattern, or the fix requires anything outside that enum (disk full, data corruption, code bug, config error), you MUST return NO_SAFE_ACTION_ESCALATE_HUMAN — never invent an action outside the enum.'

  payload=$(jq -n \
    --arg model "$AI_LAST_RESORT_MODEL" \
    --arg sys "$system_prompt" \
    --argjson bundle "$bundle" \
    '{model:$model, reasoning_effort:"low", max_completion_tokens:600, response_format:{type:"json_object"}, messages:[{role:"system",content:$sys},{role:"user",content:($bundle|tostring)}]}')

  response=$(curl -sf -m 25 -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${OPENAI_API_KEY}" \
    -d "$payload" 2>&1) || {
    log "AI last-resort: OpenAI call failed (non-fatal)"
    notify "AI last-resort diagnosis unavailable" \
      "OpenAI call failed while issue persisted $((now - first_seen))s: $(printf '%s; ' "${issues[@]}")" "high"
    return 0
  }

  content=$(jq -r '.choices[0].message.content // empty' <<<"$response" 2>/dev/null)
  content="${content#\`\`\`json}"
  content="${content#\`\`\`}"
  content="${content%\`\`\`}"
  if [ -z "$content" ] || ! jq -e '.recommended_action' >/dev/null 2>&1 <<<"$content"; then
    log "AI last-resort: unparseable/empty response, escalating to human"
    notify "AI last-resort diagnosis failed to parse" "Raw response logged to ${STATE_DIR}/ai-incidents/ for review." "high"
    mkdir -p "$STATE_DIR/ai-incidents"
    printf '%s\n' "$response" >"$STATE_DIR/ai-incidents/$(date +%s)-unparseable.json"
    return 0
  fi

  local action confidence diagnosis
  action=$(jq -r '.recommended_action' <<<"$content")
  confidence=$(jq -r '.confidence // "unknown"' <<<"$content")
  diagnosis=$(jq -r '.diagnosis // "no diagnosis"' <<<"$content")
  case "$action" in
    RESTART_SIGNAL_BOT_FORCE_RECREATE | RESTART_POSTGRES | RESTART_REDIS | NO_SAFE_ACTION_ESCALATE_HUMAN) ;;
    *)
      log "AI last-resort: model returned an action outside the enum ($action) -- treating as escalate"
      action="NO_SAFE_ACTION_ESCALATE_HUMAN (model hallucinated: $action)"
      ;;
  esac

  mkdir -p "$STATE_DIR/ai-incidents"
  printf '%s\n' "$content" >"$STATE_DIR/ai-incidents/$(date +%s).json"

  notify "AI last-resort diagnosis (SHADOW MODE — no action taken)" \
    "Diagnosis: ${diagnosis} | Confidence: ${confidence} | Would have run: ${action}" \
    "high"
}

check_app_restart_failures() {
  [ -r "$SIGNAL_RESTART_FAILURE_LOG" ] || return 0
  local seen=0 total new_lines
  [ -r "$STATE_DIR/restart-failure-log-lines" ] && read -r seen <"$STATE_DIR/restart-failure-log-lines"
  total=$(wc -l <"$SIGNAL_RESTART_FAILURE_LOG" 2>/dev/null || echo 0)
  [ "$total" -lt "$seen" ] && seen=0 # log rotated/truncated since last run
  if [ "$total" -gt "$seen" ]; then
    new_lines=$(tail -n "+$((seen + 1))" "$SIGNAL_RESTART_FAILURE_LOG")
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      local reason err
      reason=$(jq -r '.reason // "unknown"' <<<"$line" 2>/dev/null)
      err=$(jq -r '.error // "unknown"' <<<"$line" 2>/dev/null)
      notify "In-app daemon restart failed" "reason=${reason}; error=${err}" "urgent"
    done <<<"$new_lines"
  fi
  printf '%s\n' "$total" >"$STATE_DIR/restart-failure-log-lines"
}

audit_runtime
if maybe_autoheal_signal; then
  audit_runtime
fi
report_state
maybe_ai_last_resort
check_app_restart_failures
