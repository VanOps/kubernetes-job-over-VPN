#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# WireGuard VPN Server – Entrypoint (Test Lab)
# Acts as the WireGuard server that VPN clients (sidecars) connect to.
# Bridges VPN clients into the vpn-backend-net where remote-host lives.
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

export TZ="${TZ:-Europe/Madrid}"

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_CONFIG_PATH="${WG_CONFIG_PATH:-/etc/wireguard/${WG_INTERFACE}.conf}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-10}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [VPN-SERVER] $*"
}

cleanup() {
  log "SIGTERM received — bringing down ${WG_INTERFACE}..."
  wg-quick down "${WG_INTERFACE}" 2>/dev/null || true
  log "VPN server stopped cleanly."
}

trap cleanup TERM INT QUIT

# ── Pre-flight checks ──────────────────────────────────────────────
if [[ ! -f "${WG_CONFIG_PATH}" ]]; then
  log "ERROR: No WireGuard config at '${WG_CONFIG_PATH}'."
  log "  → Run test/vpn-lab/setup.sh to generate keys and configs."
  exit 1
fi

if grep -qE 'SERVER_PRIVATE_KEY|CLIENT_PUBLIC_KEY|CHANGE_ME' "${WG_CONFIG_PATH}" 2>/dev/null; then
  log "ERROR: Config still contains placeholder values."
  log "  → Run test/vpn-lab/setup.sh to generate real keys."
  exit 1
fi

chmod 600 "${WG_CONFIG_PATH}"

# ── Enable IP forwarding ───────────────────────────────────────────
# (Also set via sysctls in docker-compose, but belt-and-suspenders)
log "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

# ── Bring up WireGuard server ──────────────────────────────────────
log "Starting WireGuard server interface '${WG_INTERFACE}'..."
if ! wg-quick up "${WG_INTERFACE}"; then
  log "ERROR: wg-quick up failed. Verify NET_ADMIN capability and config."
  exit 1
fi

log "Interface '${WG_INTERFACE}' is UP."
touch /tmp/vpn-server-ready

log "=== WireGuard Status ==="
wg show "${WG_INTERFACE}" 2>/dev/null || true
log "========================"

# ── Monitor loop ───────────────────────────────────────────────────
log "Entering monitor loop (interval: ${MONITOR_INTERVAL}s)..."
while true; do
  if ! ip link show "${WG_INTERFACE}" &>/dev/null; then
    log "WARNING: Interface '${WG_INTERFACE}' disappeared. Restarting..."
    wg-quick up "${WG_INTERFACE}" || {
      log "ERROR: Failed to restart WireGuard. Exiting."
      exit 1
    }
    log "Interface restarted successfully."
  fi
  sleep "${MONITOR_INTERVAL}" & wait $!
done
