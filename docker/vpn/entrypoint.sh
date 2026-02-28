#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# WireGuard VPN Sidecar – Entrypoint
# Runs as Kubernetes native sidecar (initContainer with restartPolicy: Always)
# All containers in the Pod share this network namespace.
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

export TZ="${TZ:-Europe/Madrid}"

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_CONFIG_PATH="${WG_CONFIG_PATH:-/etc/wireguard/${WG_INTERFACE}.conf}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-10}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [VPN-SIDECAR] $*"
}

cleanup() {
  log "SIGTERM received — bringing down ${WG_INTERFACE}..."
  wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
  log "VPN sidecar stopped cleanly."
}

trap cleanup TERM INT QUIT

# ── Skip mode (local testing without a real WireGuard server) ──────
# Set SKIP_VPN=true in docker-compose environment OR when wg0.conf
# is missing or still has placeholder values.
_has_placeholder() {
  grep -qE 'CHANGE_ME|CLIENT_PRIVATE_KEY_BASE64|SERVER_PUBLIC_KEY_BASE64' \
    "${WG_CONFIG_PATH}" 2>/dev/null
}

if [[ "${SKIP_VPN:-false}" == "true" ]]; then
  log "SKIP_VPN=true — running in no-op mode (no WireGuard tunnel)."
  log "Set SKIP_VPN=false and provide a real wg0.conf for full VPN testing."
  touch /tmp/vpn-ready
  while true; do sleep 30 & wait $!; done
fi

if [[ ! -f "${WG_CONFIG_PATH}" ]]; then
  log "WARNING: No wg0.conf found at '${WG_CONFIG_PATH}'."
  log "  → Running in no-op mode. Mount a real WireGuard config to enable VPN."
  log "  → For K8s: kubectl create secret generic vpn-wireguard-config --from-file=wg0.conf=..."
  touch /tmp/vpn-ready
  while true; do sleep 30 & wait $!; done
fi

if _has_placeholder; then
  log "WARNING: wg0.conf contains placeholder values (not edited yet)."
  log "  → Running in no-op mode. Edit test/vpn/wg0.conf with real credentials."
  touch /tmp/vpn-ready
  while true; do sleep 30 & wait $!; done
fi

# WireGuard config must be 0600
chmod 600 "${WG_CONFIG_PATH}"

# ── Bring up interface ─────────────────────────────────────────────
log "Starting WireGuard interface '${WG_INTERFACE}'..."
if ! wg-quick up "${WG_INTERFACE}"; then
  log "ERROR: wg-quick up failed. Check your wg0.conf and NET_ADMIN capability."
  log "  Tip: set SKIP_VPN=true in docker-compose for local testing without VPN."
  exit 1
fi
log "Interface '${WG_INTERFACE}' is UP."
touch /tmp/vpn-ready   # signal healthcheck

log "=== WireGuard Status ==="
wg show "${WG_INTERFACE}" 2>/dev/null || true
log "========================"

# ── Monitor loop (keeps sidecar container running) ─────────────────
log "Entering monitor loop (interval: ${MONITOR_INTERVAL}s)..."
while true; do
  if ! ip link show "${WG_INTERFACE}" &>/dev/null; then
    log "WARNING: Interface '${WG_INTERFACE}' disappeared. Attempting restart..."
    wg-quick up "${WG_INTERFACE}" || {
      log "ERROR: Failed to restart WireGuard. Exiting with code 1."
      exit 1
    }
    log "Interface '${WG_INTERFACE}' restarted successfully."
  fi
  sleep "${MONITOR_INTERVAL}" &
  wait $!
done
