#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1090
source "${REPO_DIR}/.env"
RUNTIME_FILE="${PDNSSTACK_BASE_DIR}/config/runtime.env"
if [[ -f "${RUNTIME_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_FILE}"
else
  ENABLE_CACHE_NGN=false
fi

systemctl daemon-reload
systemctl enable --now pdnsstack-net-network.service
systemctl enable --now pdnsstack-db.service

echo "[INFO] Waiting for MariaDB readiness..."
for i in {1..60}; do
  if podman exec "${DB_CONTAINER}" mariadb-admin ping -uroot -p"${PDNSSTACK_DB_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
    echo "[INFO] MariaDB is ready."
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "[ERROR] MariaDB did not become ready."
    exit 1
  fi
  sleep 2
done

podman exec -i "${DB_CONTAINER}" mariadb -uroot -p"${PDNSSTACK_DB_ROOT_PASSWORD}" < "${PDNSSTACK_BASE_DIR}/config/db/init.sql" || true

systemctl enable --now pdnsstack-auth.service
systemctl enable --now pdnsstack-poweradmin.service
systemctl enable --now pdnsstack-cache-int.service
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  systemctl enable --now pdnsstack-cache-ngn.service
else
  systemctl disable --now pdnsstack-cache-ngn.service 2>/dev/null || true
fi
systemctl enable --now pdnsstack-dnsdist.service
systemctl enable --now pdnsstack-backup.timer

echo "[INFO] Startup completed."
echo "[INFO] Next steps:"
echo "       sudo ./scripts/04-security-prepare.sh"
echo "       sudo ./scripts/05-healthcheck.sh"
echo "       sudo ./scripts/06-security-verify.sh"
