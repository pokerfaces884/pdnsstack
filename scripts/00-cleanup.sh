#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

PDNSSTACK_MODULE_PREFIX="${PDNSSTACK_MODULE_PREFIX:-pdnsstack}"
PDNSSTACK_QUADLET_DIR="${PDNSSTACK_QUADLET_DIR:-/etc/containers/systemd}"

MODULES=(
  "${PDNSSTACK_NETWORK_NAME:-${PDNSSTACK_MODULE_PREFIX}-net}"
  "${PDNSSTACK_POD_NAME:-${PDNSSTACK_MODULE_PREFIX}-pod}"
  "${PDNSSTACK_DNSDIST_NAME:-${PDNSSTACK_MODULE_PREFIX}-dnsdist}"
  "${PDNSSTACK_CACHE_INT_NAME:-${PDNSSTACK_MODULE_PREFIX}-cache-int}"
  "${PDNSSTACK_CACHE_NGN_NAME:-${PDNSSTACK_MODULE_PREFIX}-cache-ngn}"
  "${PDNSSTACK_AUTH_NAME:-${PDNSSTACK_MODULE_PREFIX}-auth}"
  "${PDNSSTACK_DB_NAME:-${PDNSSTACK_MODULE_PREFIX}-db}"
  "${PDNSSTACK_POWERADMIN_NAME:-${PDNSSTACK_MODULE_PREFIX}-poweradmin}"
  "${PDNSSTACK_BACKUP_NAME:-${PDNSSTACK_MODULE_PREFIX}-backup}"
)

UNIT_SUFFIXES=(service timer)
QUADLET_SUFFIXES=(container network pod volume service timer)

echo "[INFO] Cleanup pdnsstack modules only."
echo "[INFO] Quadlet dir: ${PDNSSTACK_QUADLET_DIR}"

for module in "${MODULES[@]}"; do
  for suffix in "${UNIT_SUFFIXES[@]}"; do
    unit="${module}.${suffix}"
    systemctl disable --now "${unit}" >/dev/null 2>&1 || true
    systemctl stop "${unit}" >/dev/null 2>&1 || true
  done
done

for module in "${MODULES[@]}"; do
  for suffix in "${QUADLET_SUFFIXES[@]}"; do
    target="${PDNSSTACK_QUADLET_DIR}/${module}.${suffix}"
    if [[ -e "${target}" || -L "${target}" ]]; then
      echo "[INFO] Remove: ${target}"
      rm -f "${target}"
    fi
  done
done

systemctl daemon-reload
systemctl reset-failed || true

echo "[INFO] Cleanup finished. Data and backup directories were not removed."
