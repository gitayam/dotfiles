#!/bin/sh
# wg-labyrinth container entrypoint.
# Brings up wg-quick at start, brings it down cleanly on SIGTERM/SIGINT.

set -eu

CONF="${WG_CONF:-/etc/wireguard/wg0.conf}"
HOP_NAME="${HOP_NAME:-unknown}"

log() { printf '[entrypoint:%s] %s\n' "$HOP_NAME" "$*"; }

if [ ! -r "$CONF" ]; then
  log "FATAL: $CONF not readable"
  exit 1
fi

cleanup() {
  log "caught signal, bringing wg-quick down"
  wg-quick down "$CONF" 2>/dev/null || true
  exit 0
}
trap cleanup TERM INT

log "starting wg-quick up $CONF"
wg-quick up "$CONF"

log "wg state:"
wg show wg0 2>&1 | sed 's/^/    /'
log "routing:"
ip route show 2>&1 | sed 's/^/    /'

log "ready; sleeping until signal"
sleep infinity &
wait $!
