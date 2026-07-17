#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1090
source "${REPO_DIR}/.env"
RUNTIME_FILE="${REPO_DIR}/config/runtime.env"
if [[ -f "${RUNTIME_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_FILE}"
else
  ENABLE_CACHE_NGN=false
fi

mkdir -p "${PDNSSTACK_BASE_DIR}"/{config,data,backup}
for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/config/${d}"
done
for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/data/${d}"
done
mkdir -p "${PDNSSTACK_BASE_DIR}/backup/db"

cp -f "${REPO_DIR}/.env" "${PDNSSTACK_BASE_DIR}/.env"
chmod 600 "${PDNSSTACK_BASE_DIR}/.env"
cp -f "${REPO_DIR}/config/runtime.env" "${PDNSSTACK_BASE_DIR}/config/runtime.env"

for d in dnsdist cache-int auth db poweradmin; do
  rsync -a --delete "${REPO_DIR}/config/${d}/" "${PDNSSTACK_BASE_DIR}/config/${d}/"
done
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  rsync -a --delete "${REPO_DIR}/config/cache-ngn/" "${PDNSSTACK_BASE_DIR}/config/cache-ngn/"
else
  rm -rf "${PDNSSTACK_BASE_DIR}/config/cache-ngn"/*
fi

mkdir -p "${QUADLET_DIR}" "${SYSTEMD_DIR}"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-net.network" "${QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-dnsdist.container" "${QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-cache-int.container" "${QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-auth.container" "${QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-db.container" "${QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/pdnsstack-poweradmin.container" "${QUADLET_DIR}/"
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  cp -f "${REPO_DIR}/config/quadlet/pdnsstack-cache-ngn.container" "${QUADLET_DIR}/"
else
  rm -f "${QUADLET_DIR}/pdnsstack-cache-ngn.container"
fi
cp -f "${REPO_DIR}/config/systemd/pdnsstack-backup.service" "${SYSTEMD_DIR}/"
cp -f "${REPO_DIR}/config/systemd/pdnsstack-backup.timer" "${SYSTEMD_DIR}/"

chmod 700 "${PDNSSTACK_BASE_DIR}/data/db"
chmod 755 "${PDNSSTACK_BASE_DIR}" "${PDNSSTACK_BASE_DIR}/config" "${PDNSSTACK_BASE_DIR}/data" "${PDNSSTACK_BASE_DIR}/backup"
chmod 600 "${PDNSSTACK_BASE_DIR}/config/db/init.sql" || true
chmod 600 "${PDNSSTACK_BASE_DIR}/config/poweradmin/config.inc.php" || true

if command -v restorecon >/dev/null 2>&1; then
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t container_file_t "${PDNSSTACK_BASE_DIR}(/.*)?" 2>/dev/null || true
  fi
  restorecon -Rv "${PDNSSTACK_BASE_DIR}" || true
fi
systemctl daemon-reload

echo "[INFO] Deployment completed."
