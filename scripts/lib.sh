#!/usr/bin/env bash
set -euo pipefail

load_env() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  ENV_FILE="${REPO_DIR}/.env"
  if [[ ! -f "${ENV_FILE}" ]]; then
    echo "[ERROR] .env not found. Copy .env.sample to .env and edit values."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
}

load_runtime_from_repo() {
  RUNTIME_FILE="${REPO_DIR}/config/runtime.env"
  if [[ -f "${RUNTIME_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNTIME_FILE}"
  else
    # shellcheck disable=SC2034
    ENABLE_CACHE_NGN=false
  fi
}

load_runtime_from_base() {
  RUNTIME_FILE="${PDNSSTACK_BASE_DIR}/config/runtime.env"
  if [[ -f "${RUNTIME_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNTIME_FILE}"
  else
    # shellcheck disable=SC2034
    ENABLE_CACHE_NGN=false
  fi
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root."
    exit 1
  fi
}

validate_version_format() {
  local variable_name="$1"
  local value="$2"
  local format="$3"
  local pattern description

  case "${format}" in
    major_minor)
      pattern='^[0-9]+\.[0-9]+$'
      description='major.minor (e.g. 5.2)'
      ;;
    semver)
      pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
      description='semantic version (e.g. 4.4.0)'
      ;;
    *)
      echo "[ERROR] Unknown version format validator: ${format}"
      return 1
      ;;
  esac

  if ! [[ "${value}" =~ ${pattern} ]]; then
    echo "[ERROR] Invalid version format for ${variable_name}: ${value}"
    echo "        Expected ${description}"
    return 1
  fi
}

derive_auth_image_from_version() {
  local version="$1"
  printf 'docker.io/powerdns/pdns-auth-%s\n' "${version//./}"
}

derive_auth_schema_ref() {
  local version="$1"
  local override="${2:-}"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
  else
    printf 'rel-auth-%s.x\n' "${version}"
  fi
}

derive_poweradmin_schema_ref() {
  local version="$1"
  local override="${2:-}"
  if [[ -n "${override}" ]]; then
    printf '%s\n' "${override}"
  else
    printf 'v%s\n' "${version}"
  fi
}

wait_for_mariadb() {
  local container_name="$1"
  local root_password="$2"
  local max_attempts="${3:-60}"
  local sleep_seconds="${4:-2}"
  local attempt

  echo "[INFO] Waiting for MariaDB readiness..."
  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if podman exec "${container_name}" mariadb-admin ping -uroot -p"${root_password}" --silent >/dev/null 2>&1; then
      echo "[INFO] MariaDB is ready."
      return 0
    fi

    if [[ "${attempt}" -eq "${max_attempts}" ]]; then
      echo "[ERROR] MariaDB did not become ready."
      return 1
    fi

    sleep "${sleep_seconds}"
  done
}

check_table_exists() {
  local container_name="$1"
  local db_user="$2"
  local db_password="$3"
  local db_name="$4"
  local table_name="$5"
  local result

  result="$(
    podman exec "${container_name}" mariadb \
      -u"${db_user}" \
      -p"${db_password}" \
      -Nse "SELECT 1 FROM information_schema.tables WHERE table_schema='${db_name}' AND table_name='${table_name}' LIMIT 1;" \
      2>/dev/null || true
  )"

  [[ "${result}" == "1" ]]
}
