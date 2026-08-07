#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
RUNTIME_FILE="${REPO_DIR}/config/runtime.env"
LIB_FILE="${SCRIPT_DIR}/lib.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] This script is intended for rootful deployment."
  echo "        Please run with sudo."
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] .env file not found: ${ENV_FILE}"
  echo "        Please copy .env.sample to .env and edit it."
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

# shellcheck source=/dev/null
source "${LIB_FILE}"

PDNSSTACK_AUTH_VERSION="${PDNSSTACK_AUTH_VERSION:-5.2}"
PDNSSTACK_POWERADMIN_VERSION="${PDNSSTACK_POWERADMIN_VERSION:-4.4.0}"

validate_version_format "PDNSSTACK_AUTH_VERSION" "${PDNSSTACK_AUTH_VERSION}" "major_minor"
validate_version_format "PDNSSTACK_POWERADMIN_VERSION" "${PDNSSTACK_POWERADMIN_VERSION}" "semver"

if [[ ! -f "${RUNTIME_FILE}" ]]; then
  echo "[ERROR] runtime.env not found: ${RUNTIME_FILE}"
  echo "        Please run scripts/01-create.sh first."
  exit 1
fi

# shellcheck disable=SC1090
source "${RUNTIME_FILE}"

required_vars=(
  PDNSSTACK_BASE_DIR
  PDNSSTACK_QUADLET_DIR
  PDNSSTACK_SYSTEMD_DIR

  ENABLE_CACHE_NGN

  PDNSSTACK_NETWORK_NAME
  PDNSSTACK_DNSDIST_NAME
  PDNSSTACK_CACHE_INT_NAME
  PDNSSTACK_CACHE_NGN_NAME
  PDNSSTACK_AUTH_NAME
  PDNSSTACK_DB_NAME
  PDNSSTACK_POWERADMIN_NAME
  PDNSSTACK_BACKUP_NAME
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] Required variable is empty: ${var}"
    exit 1
  fi
done

echo "[INFO] Starting rootful deployment."
echo "[INFO] Base directory: ${PDNSSTACK_BASE_DIR}"
echo "[INFO] Quadlet directory: ${PDNSSTACK_QUADLET_DIR}"
echo "[INFO] Systemd directory: ${PDNSSTACK_SYSTEMD_DIR}"
echo "[INFO] ENABLE_CACHE_NGN=${ENABLE_CACHE_NGN}"

mkdir -p "${PDNSSTACK_BASE_DIR}"/{config,data,backup}
mkdir -p "${PDNSSTACK_BASE_DIR}/config/schema"

for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/config/${d}"
done

for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/data/${d}"
done

mkdir -p "${PDNSSTACK_BASE_DIR}/backup/db"

cp -f "${ENV_FILE}" "${PDNSSTACK_BASE_DIR}/.env"
chmod 600 "${PDNSSTACK_BASE_DIR}/.env"

echo "[INFO] DEBUG"

cp -f "${RUNTIME_FILE}" "${PDNSSTACK_BASE_DIR}/config/runtime.env"
chmod 644 "${PDNSSTACK_BASE_DIR}/config/runtime.env" || true

for d in dnsdist cache-int auth db poweradmin; do
  if [[ ! -d "${REPO_DIR}/config/${d}" ]]; then
    echo "[ERROR] Required config directory not found: ${REPO_DIR}/config/${d}"
    exit 1
  fi

  rsync -a --delete "${REPO_DIR}/config/${d}/" "${PDNSSTACK_BASE_DIR}/config/${d}/"
done

if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  if [[ ! -d "${REPO_DIR}/config/cache-ngn" ]]; then
    echo "[ERROR] cache-ngn is enabled but config directory not found: ${REPO_DIR}/config/cache-ngn"
    exit 1
  fi

  rsync -a --delete "${REPO_DIR}/config/cache-ngn/" "${PDNSSTACK_BASE_DIR}/config/cache-ngn/"
else
  rm -rf "${PDNSSTACK_BASE_DIR}/config/cache-ngn"/*
fi

mkdir -p "${PDNSSTACK_QUADLET_DIR}"
mkdir -p "${PDNSSTACK_SYSTEMD_DIR}"

cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_NETWORK_NAME}.network" "${PDNSSTACK_QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_DNSDIST_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_CACHE_INT_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_AUTH_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_DB_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"
cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_POWERADMIN_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"

if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  cp -f "${REPO_DIR}/config/quadlet/${PDNSSTACK_CACHE_NGN_NAME}.container" "${PDNSSTACK_QUADLET_DIR}/"
else
  rm -f "${PDNSSTACK_QUADLET_DIR}/${PDNSSTACK_CACHE_NGN_NAME}.container"
fi

cp -f "${REPO_DIR}/config/systemd/${PDNSSTACK_BACKUP_NAME}.service" "${PDNSSTACK_SYSTEMD_DIR}/"
cp -f "${REPO_DIR}/config/systemd/${PDNSSTACK_BACKUP_NAME}.timer" "${PDNSSTACK_SYSTEMD_DIR}/"

chmod 700 "${PDNSSTACK_BASE_DIR}/data/db"
chmod 755 \
  "${PDNSSTACK_BASE_DIR}" \
  "${PDNSSTACK_BASE_DIR}/config" \
  "${PDNSSTACK_BASE_DIR}/data" \
  "${PDNSSTACK_BASE_DIR}/backup"

chmod 600 "${PDNSSTACK_BASE_DIR}/config/db/init.sql" || true
chmod 600 "${PDNSSTACK_BASE_DIR}/config/poweradmin/config.inc.php" || true

# =========================================================
# Version-driven schema download
# =========================================================

PDNSSTACK_AUTH_IMAGE_RESOLVED="${PDNSSTACK_AUTH_IMAGE_FULL:-$(derive_auth_image_from_version "${PDNSSTACK_AUTH_VERSION}")}"
PDNSSTACK_POWERADMIN_IMAGE_RESOLVED="${PDNSSTACK_POWERADMIN_IMAGE_FULL:-docker.io/poweradmin/poweradmin:${PDNSSTACK_POWERADMIN_VERSION}}"
PDNSSTACK_AUTH_SCHEMA_REF_RESOLVED="$(
  derive_auth_schema_ref \
    "${PDNSSTACK_AUTH_VERSION}" \
    "${PDNSSTACK_AUTH_SCHEMA_REF:-${PDNSSTACK_PDNS_SCHEMA_REF:-}}"
)"
PDNSSTACK_POWERADMIN_SCHEMA_REF_RESOLVED="$(
  derive_poweradmin_schema_ref \
    "${PDNSSTACK_POWERADMIN_VERSION}" \
    "${PDNSSTACK_POWERADMIN_SCHEMA_REF:-}"
)"

PDNSSTACK_SCHEMA_DIR="${PDNSSTACK_BASE_DIR}/config/schema"
PDNS_GMYSQL_SCHEMA_FILE="${PDNSSTACK_SCHEMA_DIR}/pdns-auth-gmysql-schema.mysql.sql"
POWERADMIN_SCHEMA_FILE="${PDNSSTACK_SCHEMA_DIR}/poweradmin-mysql-db-structure.sql"
PDNS_GMYSQL_SCHEMA_URL="https://raw.githubusercontent.com/PowerDNS/pdns/${PDNSSTACK_AUTH_SCHEMA_REF_RESOLVED}/modules/gmysqlbackend/schema.mysql.sql"
POWERADMIN_SCHEMA_URL="https://raw.githubusercontent.com/poweradmin/poweradmin/${PDNSSTACK_POWERADMIN_SCHEMA_REF_RESOLVED}/sql/poweradmin-mysql-db-structure.sql"

echo "[INFO] PowerDNS Authoritative version: ${PDNSSTACK_AUTH_VERSION}"
echo "[INFO] PowerDNS Authoritative image: ${PDNSSTACK_AUTH_IMAGE_RESOLVED}"
echo "[INFO] PowerDNS Authoritative schema ref: ${PDNSSTACK_AUTH_SCHEMA_REF_RESOLVED}"
echo "[INFO] PowerDNS Authoritative schema URL: ${PDNS_GMYSQL_SCHEMA_URL}"
echo "[INFO] PowerAdmin version: ${PDNSSTACK_POWERADMIN_VERSION}"
echo "[INFO] PowerAdmin image: ${PDNSSTACK_POWERADMIN_IMAGE_RESOLVED}"
echo "[INFO] PowerAdmin schema ref: ${PDNSSTACK_POWERADMIN_SCHEMA_REF_RESOLVED}"
echo "[INFO] PowerAdmin schema URL: ${POWERADMIN_SCHEMA_URL}"

for download in \
  "${PDNS_GMYSQL_SCHEMA_URL}|${PDNS_GMYSQL_SCHEMA_FILE}|PowerDNS Authoritative" \
  "${POWERADMIN_SCHEMA_URL}|${POWERADMIN_SCHEMA_FILE}|PowerAdmin"; do
  IFS='|' read -r schema_url schema_file schema_name <<< "${download}"
  echo "[INFO] Downloading ${schema_name} schema to ${schema_file}"
  if ! curl -fsSL "${schema_url}" -o "${schema_file}"; then
    echo "[ERROR] Failed to download ${schema_name} schema."
    echo "        URL: ${schema_url}"
    exit 1
  fi
  if [[ ! -s "${schema_file}" ]]; then
    echo "[ERROR] Downloaded ${schema_name} schema file is empty: ${schema_file}"
    exit 1
  fi
  chmod 644 "${schema_file}"
done

if command -v restorecon >/dev/null 2>&1; then
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t container_file_t "${PDNSSTACK_BASE_DIR}(/.*)?" 2>/dev/null || true
  fi

  restorecon -Rv "${PDNSSTACK_BASE_DIR}" || true
fi

systemctl daemon-reload

echo "[INFO] Deployment completed."
