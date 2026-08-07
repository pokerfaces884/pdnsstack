#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_FILE="${SCRIPT_DIR}/lib.sh"
# shellcheck source=/dev/null
source "${LIB_FILE}"
# shellcheck disable=SC1090
source "${REPO_DIR}/.env"
RUNTIME_FILE="${PDNSSTACK_BASE_DIR}/config/runtime.env"
if [[ -f "${RUNTIME_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_FILE}"
else
  ENABLE_CACHE_NGN=false
fi

DB_DATA_DIR="${PDNSSTACK_BASE_DIR}/data/db"
if [[ -d "${DB_DATA_DIR}" ]] && find "${DB_DATA_DIR}" -mindepth 1 -print -quit | grep -q .; then
  echo "[WARN] Existing MariaDB data detected in ${DB_DATA_DIR}."
  echo "[WARN] MariaDB root password changes are applied only on first initialization."
  echo "[WARN] If you changed PDNSSTACK_DB_ROOT_PASSWORD, reinitialize ${DB_DATA_DIR} before startup."
fi

systemctl daemon-reload
systemctl enable --now "${PDNSSTACK_NETWORK_SERVICE}"
systemctl enable --now "${PDNSSTACK_DB_SERVICE}"

wait_for_mariadb "${PDNSSTACK_DB_NAME}" "${PDNSSTACK_DB_ROOT_PASSWORD}"

podman exec -i "${PDNSSTACK_DB_NAME}" mariadb -uroot -p"${PDNSSTACK_DB_ROOT_PASSWORD}" < "${PDNSSTACK_BASE_DIR}/config/db/init.sql" || true

# =========================================================
# Schema import
# =========================================================

PDNSSTACK_AUTH_VERSION="${PDNSSTACK_AUTH_VERSION:-5.2}"
PDNSSTACK_POWERADMIN_VERSION="${PDNSSTACK_POWERADMIN_VERSION:-4.4.0}"

validate_version_format "PDNSSTACK_AUTH_VERSION" "${PDNSSTACK_AUTH_VERSION}" "major_minor"
validate_version_format "PDNSSTACK_POWERADMIN_VERSION" "${PDNSSTACK_POWERADMIN_VERSION}" "semver"

PDNS_GMYSQL_SCHEMA_FILE="${PDNSSTACK_BASE_DIR}/config/schema/pdns-auth-gmysql-schema.mysql.sql"
POWERADMIN_SCHEMA_FILE="${PDNSSTACK_BASE_DIR}/config/schema/poweradmin-mysql-db-structure.sql"

if check_table_exists \
 "${PDNSSTACK_DB_NAME}" \
 "${PDNSSTACK_AUTH_DB_USER}" \
 "${PDNSSTACK_AUTH_DB_PASSWORD}" \
 "${PDNSSTACK_AUTH_DB_NAME}" \
 "domains"; then
 echo "[INFO] PowerDNS gmysql schema already exists. Skipping schema import."
else
 if [[ ! -f "${PDNS_GMYSQL_SCHEMA_FILE}" ]]; then
   echo "[ERROR] PowerDNS gmysql schema file not found: ${PDNS_GMYSQL_SCHEMA_FILE}"
   exit 1
 fi

 echo "[INFO] Importing PowerDNS gmysql schema..."
 if ! podman exec -i "${PDNSSTACK_DB_NAME}" mariadb \
   -u"${PDNSSTACK_AUTH_DB_USER}" \
   -p"${PDNSSTACK_AUTH_DB_PASSWORD}" \
   -D"${PDNSSTACK_AUTH_DB_NAME}" \
   < "${PDNS_GMYSQL_SCHEMA_FILE}"; then
   echo "[ERROR] Failed to import PowerDNS gmysql schema."
   exit 1
 fi
 echo "[INFO] PowerDNS gmysql schema imported successfully."
fi

if check_table_exists \
 "${PDNSSTACK_DB_NAME}" \
 "${PDNSSTACK_POWERADMIN_DB_USER}" \
 "${PDNSSTACK_POWERADMIN_DB_PASSWORD}" \
 "${PDNSSTACK_POWERADMIN_DB_NAME}" \
 "users"; then
 echo "[INFO] PowerAdmin schema already exists. Skipping schema import."
else
 if [[ ! -f "${POWERADMIN_SCHEMA_FILE}" ]]; then
   echo "[ERROR] PowerAdmin schema file not found: ${POWERADMIN_SCHEMA_FILE}"
   exit 1
 fi

 echo "[INFO] Importing PowerAdmin schema..."
 if ! podman exec -i "${PDNSSTACK_DB_NAME}" mariadb \
   -u"${PDNSSTACK_POWERADMIN_DB_USER}" \
   -p"${PDNSSTACK_POWERADMIN_DB_PASSWORD}" \
   -D"${PDNSSTACK_POWERADMIN_DB_NAME}" \
   < "${POWERADMIN_SCHEMA_FILE}"; then
   echo "[ERROR] Failed to import PowerAdmin schema."
   exit 1
 fi
 echo "[INFO] PowerAdmin schema imported successfully."
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
