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
    ENABLE_CACHE_NGN=false
  fi
}

load_runtime_from_base() {
  RUNTIME_FILE="${BASE_DIR}/config/runtime.env"
  if [[ -f "${RUNTIME_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${RUNTIME_FILE}"
  else
    ENABLE_CACHE_NGN=false
  fi
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] This script must be run as root."
    exit 1
  fi
}
