#!/usr/bin/env bash
# Standalone VPN wait helper (usable from init containers or CI scripts)
set -euo pipefail

VPN_INTERFACE="${VPN_INTERFACE:-wg0}"
TIMEOUT="${VPN_WAIT_TIMEOUT:-60}"
INTERVAL=2
elapsed=0

echo "[wait-for-vpn] Waiting for '${VPN_INTERFACE}' (timeout: ${TIMEOUT}s)..."
while ! ip link show "${VPN_INTERFACE}" up &>/dev/null; do
  if [[ ${elapsed} -ge ${TIMEOUT} ]]; then
    echo "[wait-for-vpn] TIMEOUT: '${VPN_INTERFACE}' not up after ${TIMEOUT}s."
    exit 1
  fi
  sleep "${INTERVAL}"
  elapsed=$((elapsed + INTERVAL))
done

echo "[wait-for-vpn] '${VPN_INTERFACE}' is UP after ${elapsed}s."
exit 0
