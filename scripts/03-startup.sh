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
systemctl enable --now "${PDNSSTACK_NETWORK_SERVICE}"
systemctl enable --now "${PDNSSTACK_DB_SERVICE}"

echo "[INFO] Waiting for MariaDB readiness..."
for i in {1..60}; do
  if podman exec "${PDNSSTACK_DB_NAME}" mariadb-admin ping -uroot -p"${PDNSSTACK_DB_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
    echo "[INFO] MariaDB is ready."
    break
  fi
  if [[ "${i}" -eq 60 ]]; then
    echo "[ERROR] MariaDB did not become ready."
    exit 1
  fi
  sleep 2
done

podman exec -i "${PDNSSTACK_DB_NAME}" mariadb -uroot -p"${PDNSSTACK_DB_ROOT_PASSWORD}" < "${PDNSSTACK_BASE_DIR}/config/db/init.sql" || true

# =========================================================
# PowerDNS gmysql Schema Import
# =========================================================

PDNSSTACK_PDNS_SCHEMA_SOURCE="${PDNSSTACK_PDNS_SCHEMA_SOURCE:-official}"
PDNS_GMYSQL_SCHEMA_FILE="${PDNSSTACK_BASE_DIR}/config/pdns/schema.mysql.sql"

if [[ "${PDNSSTACK_PDNS_SCHEMA_SOURCE}" != "disabled" ]] && [[ -f "${PDNS_GMYSQL_SCHEMA_FILE}" ]]; then
  echo "[INFO] Checking PowerDNS gmysql schema status..."
  
  # Check if domains table exists
  DOMAINS_TABLE_EXISTS=$(podman exec "${PDNSSTACK_DB_NAME}" mariadb \
    -u"${PDNSSTACK_AUTH_DB_USER}" \
    -p"${PDNSSTACK_AUTH_DB_PASSWORD}" \
    -D"${PDNSSTACK_AUTH_DB_NAME}" \
    -Nse "SHOW TABLES LIKE 'domains';" 2>/dev/null || echo "")
  
  if [[ -z "${DOMAINS_TABLE_EXISTS}" ]]; then
    echo "[INFO] PowerDNS gmysql schema not found. Importing schema.mysql.sql..."
    if podman exec -i "${PDNSSTACK_DB_NAME}" mariadb \
      -u"${PDNSSTACK_AUTH_DB_USER}" \
      -p"${PDNSSTACK_AUTH_DB_PASSWORD}" \
      -D"${PDNSSTACK_AUTH_DB_NAME}" \
      < "${PDNS_GMYSQL_SCHEMA_FILE}"; then
      echo "[INFO] PowerDNS gmysql schema imported successfully."
      
      # Verify tables were created
      TABLES_COUNT=$(podman exec "${PDNSSTACK_DB_NAME}" mariadb \
        -u"${PDNSSTACK_AUTH_DB_USER}" \
        -p"${PDNSSTACK_AUTH_DB_PASSWORD}" \
        -D"${PDNSSTACK_AUTH_DB_NAME}" \
        -Nse "SHOW TABLES;" | wc -l)
      
      echo "[INFO] Created ${TABLES_COUNT} PowerDNS tables."
    else
      echo "[ERROR] Failed to import PowerDNS gmysql schema."
      exit 1
    fi
  else
    echo "[INFO] PowerDNS gmysql schema already exists. Skipping schema import."
  fi
elif [[ "${PDNSSTACK_PDNS_SCHEMA_SOURCE}" == "disabled" ]]; then
  echo "[INFO] PowerDNS gmysql schema import is disabled."
else
  echo "[WARN] PowerDNS gmysql schema file not found: ${PDNS_GMYSQL_SCHEMA_FILE}"
  echo "[WARN] Skipping schema import. Make sure the schema is already created in the database."
fi

systemctl enable --now "${PDNSSTACK_AUTH_SERVICE}"
systemctl enable --now "${PDNSSTACK_POWERADMIN_SERVICE}"
systemctl enable --now "${PDNSSTACK_CACHE_INT_SERVICE}"
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  systemctl enable --now "${PDNSSTACK_CACHE_NGN_SERVICE}"
else
  systemctl disable --now "${PDNSSTACK_CACHE_NGN_SERVICE}" 2>/dev/null || true
fi
systemctl enable --now "${PDNSSTACK_DNSDIST_SERVICE}"
systemctl enable --now "${PDNSSTACK_BACKUP_TIMER}"

echo "[INFO] Startup completed."
echo "[INFO] Next steps:"
echo "       sudo ./scripts/04-security-prepare.sh"
echo "       sudo ./scripts/05-healthcheck.sh"
echo "       sudo ./scripts/06-security-verify.sh"
