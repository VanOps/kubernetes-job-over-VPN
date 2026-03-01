#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# Remote Host – Entrypoint (Test Lab)
# Installs SSH authorized_keys from the mounted secret, then runs sshd.
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [REMOTE-HOST] $*"
}

PUBKEY_FILE="${SSH_PUBKEY_FILE:-/run/secrets/ssh-public-key}"

# ── SSH authorized_keys ────────────────────────────────────────────
if [[ -f "${PUBKEY_FILE}" ]]; then
  cp "${PUBKEY_FILE}" /home/ansible/.ssh/authorized_keys
  chmod 600 /home/ansible/.ssh/authorized_keys
  chown ansible:ansible /home/ansible/.ssh/authorized_keys
  log "authorized_keys configured from ${PUBKEY_FILE}."
else
  log "WARNING: Public key not found at '${PUBKEY_FILE}'."
  log "  → Run test/vpn-lab/setup.sh and ensure ssh-public-key is mounted."
fi

# ── SSH host keys ──────────────────────────────────────────────────
log "Generating SSH host keys (if not already present)..."
ssh-keygen -A

log "Starting SSH daemon..."
exec /usr/sbin/sshd -D -e
