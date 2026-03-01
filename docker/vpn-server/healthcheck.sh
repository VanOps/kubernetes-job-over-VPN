#!/usr/bin/env bash
# VPN server health check: passes once WireGuard interface is fully up.
[ -f /tmp/vpn-server-ready ]
