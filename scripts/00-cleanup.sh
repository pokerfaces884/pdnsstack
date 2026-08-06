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

# Prefer explicit service/timer variables if available; fall back to constructed names.
SERVICE_UNITS=(
  "${PDNSSTACK_NETWORK_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-net-network.service}"
  "${PDNSSTACK_DB_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-db.service}"
  "${PDNSSTACK_AUTH_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-auth.service}"
  "${PDNSSTACK_POWERADMIN_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-poweradmin.service}"
  "${PDNSSTACK_CACHE_INT_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-cache-int.service}"
  "${PDNSSTACK_CACHE_NGN_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-cache-ngn.service}"
  "${PDNSSTACK_DNSDIST_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-dnsdist.service}"
  "${PDNSSTACK_BACKUP_SERVICE:-${PDNSSTACK_MODULE_PREFIX}-backup.service}"
  "${PDNSSTACK_BACKUP_TIMER:-${PDNSSTACK_MODULE_PREFIX}-backup.timer}"
)

QUADLET_SUFFIXES=(container network pod volume service timer)

echo "[INFO] Cleanup pdnsstack modules only."
echo "[INFO] Quadlet dir: ${PDNSSTACK_QUADLET_DIR}"

for unit in "${SERVICE_UNITS[@]}"; do
  if [[ -n "${unit}" ]]; then
    systemctl disable --now "${unit}" >/dev/null 2>&1 || true
    systemctl stop "${unit}" >/dev/null 2>&1 || true
  fi
done

# Remove quadlet files by name variables if available, else fallback to pattern-based cleanup
if [[ -n "${PDNSSTACK_NETWORK_NAME:-}" ]]; then
  NAMES=(
    "${PDNSSTACK_NETWORK_NAME}"
    "${PDNSSTACK_DNSDIST_NAME}"
    "${PDNSSTACK_CACHE_INT_NAME}"
    "${PDNSSTACK_CACHE_NGN_NAME}"
    "${PDNSSTACK_AUTH_NAME}"
    "${PDNSSTACK_DB_NAME}"
    "${PDNSSTACK_POWERADMIN_NAME}"
    "${PDNSSTACK_BACKUP_NAME}"
  )
else
  NAMES=(
    "${PDNSSTACK_MODULE_PREFIX}-net"
    "${PDNSSTACK_MODULE_PREFIX}-pod"
    "${PDNSSTACK_MODULE_PREFIX}-dnsdist"
    "${PDNSSTACK_MODULE_PREFIX}-cache-int"
    "${PDNSSTACK_MODULE_PREFIX}-cache-ngn"
    "${PDNSSTACK_MODULE_PREFIX}-auth"
    "${PDNSSTACK_MODULE_PREFIX}-db"
    "${PDNSSTACK_MODULE_PREFIX}-poweradmin"
    "${PDNSSTACK_MODULE_PREFIX}-backup"
  )
fi

for name in "${NAMES[@]}"; do
  for suffix in "${QUADLET_SUFFIXES[@]}"; do
    target="${PDNSSTACK_QUADLET_DIR}/${name}.${suffix}"
    if [[ -e "${target}" || -L "${target}" ]]; then
      echo "[INFO] Remove: ${target}"
      rm -f "${target}"
    fi
  done
done

systemctl daemon-reload
systemctl reset-failed || true

echo "[INFO] Cleanup finished. Data and backup directories were not removed."
