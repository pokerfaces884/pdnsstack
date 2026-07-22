#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
RUNTIME_FILE="${REPO_DIR}/config/runtime.env"

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

for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/config/${d}"
done

for d in dnsdist cache-int cache-ngn auth db poweradmin; do
  mkdir -p "${PDNSSTACK_BASE_DIR}/data/${d}"
done

mkdir -p "${PDNSSTACK_BASE_DIR}/backup/db"

cp -f "${ENV_FILE}" "${PDNSSTACK_BASE_DIR}/.env"
chmod 600 "${PDNSSTACK_BASE_DIR}/.env"

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

if command -v restorecon >/dev/null 2>&1; then
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t container_file_t "${PDNSSTACK_BASE_DIR}(/.*)?" 2>/dev/null || true
  fi

  restorecon -Rv "${PDNSSTACK_BASE_DIR}" || true
fi

systemctl daemon-reload

echo "[INFO] Deployment completed."