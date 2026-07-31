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
STATE_DIR="/var/lib/docker-runtime-monitor"
NOTIFY_REPEAT_SECONDS=3600
AUTOHEAL_COOLDOWN_SECONDS=900
LOG_TAG="docker-runtime-monitor"

mkdir -p "$STATE_DIR"
exec 9>"/run/lock/docker-runtime-monitor.lock"
if ! flock -n 9; then
  echo "[$LOG_TAG] another monitor run is active"
  exit 0
fi

work_dir=$(mktemp -d /tmp/docker-runtime-monitor.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT

log() { echo "[$LOG_TAG] $*"; }

notify() {
  local title="$1" message="$2" priority="${3:-default}"
  local headers=(-H "Title: ${title}" -H "Priority: ${priority}")
  if [ -n "$NTFY_TOKEN" ]; then
    headers+=(-H "Authorization: Bearer ${NTFY_TOKEN}")
  fi
  curl -sf -m 10 -X POST "${NTFY_URL}/${NTFY_TOPIC}" \
    "${headers[@]}" -d "$message" >/dev/null 2>&1 || log "ntfy post failed (non-fatal)"
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
  # ready, permit one rate-limited narrow compose recovery.
  if [ "$running_unmanaged_count" -eq 0 ] && [ "$internal_ready" -eq 0 ]; then
    mark_autoheal
    (cd "$SIGNAL_COMPOSE_DIR" && docker compose up -d signal-bot) || return 1
    notify "Signal readiness auto-heal attempted" \
      "No runtime split-brain was present; restarted the canonical Signal stack." "high"
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
  printf '%s\n' "$fingerprint" >"$STATE_DIR/fingerprint"
  printf '%s\n' "$summary" >"$STATE_DIR/summary"
  return 1
}

audit_runtime
if maybe_autoheal_signal; then
  audit_runtime
fi
report_state
