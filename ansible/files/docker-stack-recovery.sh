#!/usr/bin/env bash
# Boot-time Docker stack recovery for johncloud (100.87.20.88).
# Re-registers Docker volumes, enforces the decommission denylist, and starts
# known stacks only after proving Docker controls every running containerd task.

set -uo pipefail

# shellcheck source=/dev/null
[ -r /etc/docker-stack-recovery.conf ] && source /etc/docker-stack-recovery.conf

NTFY_URL="${NTFY_URL:-http://127.0.0.1:2586}"
NTFY_TOPIC="${NTFY_TOPIC:-proxmox-recovery}"
NTFY_TOKEN="${NTFY_TOKEN:-}"
HOME_DIR="/datadrive/home"
LOG_TAG="docker-stack-recovery"

exec 9>"/run/lock/docker-stack-recovery.lock"
if ! flock -n 9; then
  echo "[$LOG_TAG] another recovery run is active"
  exit 0
fi

work_dir=$(mktemp -d /tmp/docker-stack-recovery.XXXXXX)
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

DENYLIST=(
  app
  forgejo-app forgejo-redis forgejo-runner
  linkwarden-linkwarden-1 linkwarden-postgres-1 linkwarden-meilisearch-1
)

STACKS=(
  postgres-system
  mariadb-system
  traefik-system
  headscale/deploy
  authentik
  mailcow/mailcow-dockerized
  roundcube
  gitlab
  gitlab-runner
  tak-server
  cloudtak
  ntfy
  outline/norequirement_outline
  outline/alfaren_outline
  outline/irregularchat_outline
  outline/ncfayetteville_outline
  outline/obsidian
  signal-bot-selfhosted
  jellyfin
  torrent
  jitsi
  jitsi/radio
  cryptpad
  PeerTube
  searxng
  shlink
  simplelogin-app
  simplex-bot
  simplex-server
  vaultwarden
  hermes
  honcho
  riff-render
  strudel-watch
  transcode
  muse/streaming
  uxs-portal-api
  minio-irregularchat
  cad-viewer
  calibre-web
  clamav
  Claper
  pastefy
  brother-print-server
  audio-processor
  audiobookshelfuser
  airbnb-reviews
  archive
)

wait_for_docker() {
  for _ in $(seq 1 40); do
    docker info >/dev/null 2>&1 && return 0
    sleep 3
  done
  return 1
}

reap_orphaned_task() {
  local id="$1" state
  ctr -n moby tasks kill "$id" >/dev/null 2>&1 || true
  for _ in $(seq 1 5); do
    state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
    [ "$state" != "RUNNING" ] && break
    sleep 1
  done
  state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
  if [ "$state" = "RUNNING" ]; then
    ctr -n moby tasks kill -s SIGKILL "$id" >/dev/null 2>&1 || true
    sleep 1
  fi
  ctr -n moby tasks rm "$id" >/dev/null 2>&1 || true
  ctr -n moby containers rm "$id" >/dev/null 2>&1 || true
}

# Every observed occurrence of this (07-24, 07-28, 07-29 — always right after a
# dockerd restart/recreate cycle) has been an old containerd shim left running
# after Docker replaced the container, never anything dockerd doesn't also
# have a live replacement for. Auto-reap rather than abort, but log every id's
# image for the audit trail and notify a summary so it's never silent.
require_runtime_control() {
  docker ps -aq --no-trunc | sort >"$work_dir/docker.ids"
  ctr -n moby tasks list -q | sort >"$work_dir/tasks.ids"
  comm -13 "$work_dir/docker.ids" "$work_dir/tasks.ids" >"$work_dir/unmanaged.ids"

  local running=()
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
    [ "$state" = "RUNNING" ] && running+=("$id")
  done <"$work_dir/unmanaged.ids"

  if [ "${#running[@]}" -gt 0 ]; then
    log "reaping ${#running[@]} orphaned containerd task(s) before bring-up"
    local images="" img
    for id in "${running[@]}"; do
      img=$(ctr -n moby containers info "$id" 2>/dev/null | jq -r '.Image // "unknown"' 2>/dev/null)
      images+="  ${id:0:12} ${img}"$'\n'
      reap_orphaned_task "$id"
    done
    log "reaped:
${images}"
    notify "Recovery: reaped orphaned containerd tasks" \
      "${#running[@]} orphaned task(s) found and removed before bring-up:
${images}" "default"

    # Re-check once — if anything is still stuck RUNNING after two kill passes
    # each, treat that as the genuine split-brain signal and abort rather than
    # risk a duplicate.
    docker ps -aq --no-trunc | sort >"$work_dir/docker.ids"
    ctr -n moby tasks list -q | sort >"$work_dir/tasks.ids"
    comm -13 "$work_dir/docker.ids" "$work_dir/tasks.ids" >"$work_dir/unmanaged.ids"
    running=()
    while IFS= read -r id; do
      [ -z "$id" ] && continue
      state=$(ctr -n moby tasks list | awk -v target="$id" '$1 == target { print $3 }')
      [ "$state" = "RUNNING" ] && running+=("$id")
    done <"$work_dir/unmanaged.ids"
  fi

  if [ "${#running[@]}" -gt 0 ]; then
    local message="Aborted before compose bring-up: ${#running[@]} running containerd task(s) are outside Docker control."
    log "$message"
    notify "Docker stack recovery blocked by split-brain" "$message" "urgent"
    return 1
  fi
}

reconcile_volumes() {
  log "reconciling orphaned volumes..."
  local registered disk_vols missing=0
  registered=$(docker volume ls --format '{{.Name}}' | sort)
  disk_vols=$(find "$HOME_DIR/../docker/volumes" -mindepth 1 -maxdepth 1 -type d \
    -printf '%f\n' 2>/dev/null | sort)
  while IFS= read -r volume; do
    [ -z "$volume" ] && continue
    if ! grep -qxF "$volume" <<<"$registered"; then
      if docker volume create "$volume" >/dev/null 2>&1; then
        log "re-registered orphaned volume: $volume"
        missing=$((missing + 1))
      fi
    fi
  done <<<"$disk_vols"
  log "volume reconciliation done, $missing re-registered"
}

enforce_denylist() {
  log "enforcing decommission denylist..."
  for name in "${DENYLIST[@]}"; do
    if docker inspect "$name" >/dev/null 2>&1; then
      log "WARNING: removing resurrected denylisted container '$name'"
      docker rm -f "$name" >/dev/null 2>&1
      notify "Recovery removed denylisted container" \
        "Removed '$name' after restart-policy reconciliation resurrected it." "high"
    fi
  done
}

ensure_local_image() {
  local image="$1" context="$2"

  if docker image inspect "$image" >/dev/null 2>&1; then
    return 0
  fi
  if [ ! -f "$context/Dockerfile" ]; then
    log "local image '$image' is missing and $context/Dockerfile is unavailable"
    return 1
  fi

  log "rebuilding missing local image '$image' from $context ..."
  docker build --pull=false -t "$image" "$context"
}

bring_up() {
  local directory="$1" output rc id

  if [ "$directory" = "outline/obsidian" ]; then
    ensure_local_image "si-juan:latest" \
      "$HOME_DIR/outline/obsidian/si-juan-src" || return 1
  fi

  output=$(cd "$HOME_DIR/$directory" 2>&1 && docker compose up -d 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] && grep -q "already in use by container" <<<"$output"; then
    id=$(grep -oE 'already in use by container "[a-f0-9]+"' <<<"$output" \
      | head -1 | grep -oE '[a-f0-9]{12,}')
    if [ -n "$id" ]; then
      log "zombie name-index conflict in $directory, clearing $id and retrying"
      docker rm -f "$id" >/dev/null 2>&1
      output=$(cd "$HOME_DIR/$directory" 2>&1 && docker compose up -d 2>&1)
      rc=$?
    fi
  fi
  echo "$output" | tail -3 | sed 's/^/    /'
  return "$rc"
}

verify_recovery() {
  local unhealthy restarting signal_health
  unhealthy=$(docker ps --filter health=unhealthy --format '{{.Names}}' | paste -sd, -)
  restarting=$(docker ps --filter status=restarting --format '{{.Names}}' | paste -sd, -)
  signal_health=$(curl -fsS --max-time 10 http://127.0.0.1:8082/health 2>/dev/null || true)

  if [ -n "$unhealthy" ]; then
    log "unhealthy containers after recovery: $unhealthy"
    return 1
  fi
  if [ -n "$restarting" ]; then
    log "restart-looping containers after recovery: $restarting"
    return 1
  fi
  if ! jq -e '.status == "healthy" and .database == "connected" and .bot.running == true and (.instance_id | length > 0)' \
    >/dev/null 2>&1 <<<"$signal_health"; then
    log "Signal readiness/identity verification failed after recovery"
    return 1
  fi
}

main() {
  if ! mountpoint -q /datadrive; then
    notify "Docker recovery blocked" "/datadrive is not mounted." "urgent"
    exit 1
  fi
  if ! wait_for_docker; then
    notify "Docker recovery blocked" "Docker never became ready." "urgent"
    exit 1
  fi
  require_runtime_control || exit 1

  reconcile_volumes
  enforce_denylist

  local ok=() failed=()
  for directory in "${STACKS[@]}"; do
    if [ ! -d "$HOME_DIR/$directory" ]; then
      log "skip $directory (directory missing)"
      continue
    fi
    log "bringing up $directory ..."
    if bring_up "$directory"; then
      ok+=("$directory")
    else
      failed+=("$directory")
      log "FAILED: $directory"
    fi
  done

  enforce_denylist

  local summary="Recovered ${#ok[@]}/${#STACKS[@]} stacks."
  if [ "${#failed[@]}" -gt 0 ]; then
    summary+=$'\n'"FAILED: ${failed[*]}"
  fi
  if ! verify_recovery; then
    failed+=("post-recovery-verification")
    summary+=$'\n'"Post-recovery readiness verification failed."
  fi

  if [ "${#failed[@]}" -gt 0 ]; then
    notify "Docker stack recovery failed" "$summary" "urgent"
    log "$summary"
    exit 1
  fi

  notify "Docker stack recovery complete" "$summary" "default"
  log "$summary"
}

main "$@"
