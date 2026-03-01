#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# Ansible Executor – Entrypoint
# Waits for VPN (wg0), then runs ansible-playbook.
# Exit code mirrors ansible-playbook exit code for K8s Job status.
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

export TZ="${TZ:-Europe/Madrid}"

PLAYBOOK="${1:-${ANSIBLE_PLAYBOOK:-playbooks/test-connectivity.yml}}"
INVENTORY="${ANSIBLE_INVENTORY:-inventories/dev}"
EXTRA_VARS="${ANSIBLE_EXTRA_VARS:-}"
VERBOSITY="${ANSIBLE_VERBOSITY:-0}"
TAGS="${ANSIBLE_TAGS:-}"
VPN_WAIT_TIMEOUT="${VPN_WAIT_TIMEOUT:-60}"
VPN_INTERFACE="${VPN_INTERFACE:-wg0}"
SKIP_VPN_WAIT="${SKIP_VPN_WAIT:-false}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] [ANSIBLE-EXECUTOR] $*"
}

# ── Wait for VPN interface ────────────────────────────────────────────
wait_for_vpn() {
  if [[ "${SKIP_VPN_WAIT}" == "true" ]]; then
    log "SKIP_VPN_WAIT=true – bypassing VPN check (local/test mode)."
    return 0
  fi

  local elapsed=0
  local interval=2
  log "Waiting for VPN interface '${VPN_INTERFACE}' (timeout: ${VPN_WAIT_TIMEOUT}s)..."

  while ! ip link show "${VPN_INTERFACE}" up &>/dev/null; do
    if [[ ${elapsed} -ge ${VPN_WAIT_TIMEOUT} ]]; then
      log "ERROR: '${VPN_INTERFACE}' not up after ${VPN_WAIT_TIMEOUT}s. Aborting."
      exit 1
    fi
    sleep "${interval}"
    elapsed=$((elapsed + interval))
  done

  log "VPN interface '${VPN_INTERFACE}' is UP. Proceeding."
}

# ── Vault password check ──────────────────────────────────────────────
check_vault() {
  if [[ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]]; then
    log "Vault password file found at '${ANSIBLE_VAULT_PASSWORD_FILE}'."
  else
    log "WARNING: Vault password file '${ANSIBLE_VAULT_PASSWORD_FILE}' not found."
    log "         Encrypted vars will cause playbook failure."
  fi
}

# ── Build ansible-playbook command ────────────────────────────────────
build_cmd() {
  local cmd="ansible-playbook"

  [[ -n "${INVENTORY}" ]] && cmd+=" -i ${INVENTORY}"

  if [[ ${VERBOSITY} -gt 0 ]]; then
    local v_flags
    v_flags=$(printf 'v%.0s' $(seq 1 "${VERBOSITY}"))
    cmd+=" -${v_flags}"
  fi

  [[ -n "${TAGS}" ]] && cmd+=" --tags ${TAGS}"
  [[ -n "${EXTRA_VARS}" ]] && cmd+=" --extra-vars '${EXTRA_VARS}'"
  cmd+=" ${PLAYBOOK}"
  echo "${cmd}"
}

# ── Main ──────────────────────────────────────────────────────────────
log "═══════════════════════════════════════════"
log " Ansible Executor Starting"
log " Playbook  : ${PLAYBOOK}"
log " Inventory : ${INVENTORY}"
log " Timezone  : ${TZ}"
log "═══════════════════════════════════════════"

wait_for_vpn
check_vault

CMD=$(build_cmd)
log "Running: ${CMD}"
log "───────────────────────────────────────────"

eval "${CMD}"
EXIT_CODE=$?

log "───────────────────────────────────────────"
if [[ ${EXIT_CODE} -eq 0 ]]; then
  log "Playbook SUCCEEDED (exit code: 0)"
else
  log "Playbook FAILED (exit code: ${EXIT_CODE})"
fi
log "═══════════════════════════════════════════"

exit ${EXIT_CODE}
