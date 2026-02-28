#!/usr/bin/env bash
# WireGuard health check – used by HEALTHCHECK directive and readiness probes.
# Passes when:
#   1. /tmp/vpn-ready exists (set by entrypoint on success OR in no-op/skip mode)
# The ready-file approach decouples the check from the WireGuard interface,
# allowing graceful local testing without a real VPN server (SKIP_VPN=true).
[ -f /tmp/vpn-ready ]
