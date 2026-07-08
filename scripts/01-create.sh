#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] .env file not found: ${ENV_FILE}"
  echo "        Please copy .env.sample to .env and edit it."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

required_vars=(
  PDNSSTACK_HOST_IPV4
  PDNSSTACK_INITIAL_DOMAIN
  PDNSSTACK_DB_ROOT_PASSWORD
  PDNSSTACK_AUTH_DB_NAME
  PDNSSTACK_AUTH_DB_USER
  PDNSSTACK_AUTH_DB_PASSWORD
  PDNSSTACK_POWERADMIN_DB_NAME
  PDNSSTACK_POWERADMIN_DB_USER
  PDNSSTACK_POWERADMIN_DB_PASSWORD
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] Required variable is empty: ${var}"
    exit 1
  fi
done


# Generate optional API/console/web secrets when they are left empty in .env.
generate_secret_20() {
  openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20
}

optional_secret_vars=(
  PDNSSTACK_AUTH_API_KEY
  PDNSSTACK_RECURSOR_API_KEY
  PDNSSTACK_DNSDIST_CONSOLE_KEY
  PDNSSTACK_DNSDIST_WEB_PASSWORD
)

updated_env=false
for var in "${optional_secret_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    value="$(generate_secret_20)"
    printf -v "${var}" '%s' "${value}"
    export "${var}"

    if grep -qE "^[[:space:]]*${var}=" "${ENV_FILE}"; then
      sed -i -E "s|^[[:space:]]*${var}=.*|${var}=${value}|" "${ENV_FILE}"
    else
      printf '
%s=%s
' "${var}" "${value}" >> "${ENV_FILE}"
    fi
    updated_env=true
    echo "[INFO] Auto-generated ${var} and wrote it to .env"
  fi
done

if [[ "${updated_env}" == "true" ]]; then
  chmod 600 "${ENV_FILE}" || true
fi

if ! [[ "${PDNSSTACK_INITIAL_DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "[ERROR] Invalid PDNSSTACK_INITIAL_DOMAIN: ${PDNSSTACK_INITIAL_DOMAIN}"
  echo "        Allowed characters: A-Z a-z 0-9 dot hyphen"
  exit 1
fi

echo "[INFO] Environment validation completed."
echo "[INFO] Initial domain: ${PDNSSTACK_INITIAL_DOMAIN}"
echo "[INFO] Host IPv4: ${PDNSSTACK_HOST_IPV4}"

# Keep the original create/deploy logic below this validation block when merging.
