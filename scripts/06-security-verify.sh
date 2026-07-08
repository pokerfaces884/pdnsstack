#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck disable=SC1090
source "${REPO_DIR}/.env"
RUNTIME_FILE="${BASE_DIR}/config/runtime.env"
if [[ -f "${RUNTIME_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${RUNTIME_FILE}"
else
  ENABLE_CACHE_NGN=false
fi

echo "[INFO] SELinux status"
command -v getenforce >/dev/null 2>&1 && getenforce || true

echo "[INFO] firewalld status"
if command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --state || true
  firewall-cmd --list-all || true
fi

echo "[INFO] Published ports"
podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

echo "[INFO] Listening on ${HOST_IPV4}"
ss -lntup | grep "${HOST_IPV4}" || true
ss -lnuap | grep "${HOST_IPV4}" || true

echo "[INFO] Expected host ports"
echo "  ${HOST_IPV4}:${DNSDIST_DNS_PORT}/udp,tcp"
echo "  ${HOST_IPV4}:${DB_PORT}/tcp"
echo "  ${HOST_IPV4}:${CACHE_INT_DNS_PORT}/udp,tcp"
echo "  ${HOST_IPV4}:${CACHE_INT_API_PORT}/tcp"
echo "  ${HOST_IPV4}:${PDNS_AUTH_DNS_PORT}/udp,tcp"
echo "  ${HOST_IPV4}:${PDNS_AUTH_API_PORT}/tcp"
echo "  ${HOST_IPV4}:${POWERADMIN_PORT}/tcp"
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  echo "  ${HOST_IPV4}:${CACHE_NGN_DNS_PORT}/udp,tcp"
  echo "  ${HOST_IPV4}:${CACHE_NGN_API_PORT}/tcp"
else
  echo "  pdnsstack-cache-ngn disabled"
fi

echo "[INFO] Security verification completed."
