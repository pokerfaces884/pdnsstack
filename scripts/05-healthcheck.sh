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

systemctl --no-pager --full status pdnsstack-net-network.service || true
for svc in pdnsstack-db pdnsstack-cache-int pdnsstack-auth pdnsstack-poweradmin pdnsstack-dnsdist; do
  systemctl --no-pager --full status "${svc}.service" || true
done
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  systemctl --no-pager --full status pdnsstack-cache-ngn.service || true
fi

ss -lntup | grep -E ":(${DNSDIST_DNS_PORT}|${DB_PORT}|${CACHE_INT_DNS_PORT}|${CACHE_INT_API_PORT}|${PDNS_AUTH_DNS_PORT}|${PDNS_AUTH_API_PORT}|${POWERADMIN_PORT})" || true
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  ss -lntup | grep -E ":(${CACHE_NGN_DNS_PORT}|${CACHE_NGN_API_PORT})" || true
fi

echo "[INFO] DNS via dnsdist"
dig @"${HOST_IPV4}" example.com A -p "${DNSDIST_DNS_PORT}" +short || true
dig @"${HOST_IPV4}" example.com AAAA -p "${DNSDIST_DNS_PORT}" +short || true

echo "[INFO] Direct cache-int UDP/TCP"
dig @"${HOST_IPV4}" example.com A -p "${CACHE_INT_DNS_PORT}" +short || true
dig @"${HOST_IPV4}" example.com A -p "${CACHE_INT_DNS_PORT}" +tcp +short || true

if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  echo "[INFO] Direct cache-ngn UDP/TCP"
  dig @"${HOST_IPV4}" flets-west.jp A -p "${CACHE_NGN_DNS_PORT}" +short || true
  dig @"${HOST_IPV4}" flets-west.jp A -p "${CACHE_NGN_DNS_PORT}" +tcp +short || true
fi

echo "[INFO] pdns-auth UDP/TCP"
dig @"${HOST_IPV4}" . SOA -p "${PDNS_AUTH_DNS_PORT}" +norecurse || true
dig @"${HOST_IPV4}" . SOA -p "${PDNS_AUTH_DNS_PORT}" +tcp +norecurse || true

echo "[INFO] HTTP endpoints"
curl -sS "http://${HOST_IPV4}:${CACHE_INT_API_PORT}/" >/dev/null || true
curl -sS "http://${HOST_IPV4}:${PDNS_AUTH_API_PORT}/" >/dev/null || true
curl -sS "http://${HOST_IPV4}:${POWERADMIN_PORT}/" >/dev/null || true
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  curl -sS "http://${HOST_IPV4}:${CACHE_NGN_API_PORT}/" >/dev/null || true
fi

echo "[INFO] Healthcheck completed."
