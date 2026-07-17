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

systemctl --no-pager --full status pdnsstack-net-network.service || true
for svc in pdnsstack-db pdnsstack-cache-int pdnsstack-auth pdnsstack-poweradmin pdnsstack-dnsdist; do
  systemctl --no-pager --full status "${svc}.service" || true
done
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  systemctl --no-pager --full status pdnsstack-cache-ngn.service || true
fi

ss -lntup | grep -E ":(${PDNSSTACK_DNSDIST_DNS_PORT}|${PDNSSTACK_DB_PORT}|${PDNSSTACK_CACHE_INT_DNS_PORT}|${PDNSSTACK_CACHE_INT_API_PORT}|${PDNSSTACK_AUTH_DNS_PORT}|${PDNSSTACK_AUTH_API_PORT}|${PDNSSTACK_POWERADMIN_HTTP_PORT})" || true
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  ss -lntup | grep -E ":(${PDNSSTACK_CACHE_NGN_DNS_PORT}|${PDNSSTACK_CACHE_NGN_API_PORT})" || true
fi

echo "[INFO] DNS via dnsdist"
dig @"${PDNSSTACK_HOST_IPV4}" example.com A -p "${PDNSSTACK_DNSDIST_DNS_PORT}" +short || true
dig @"${PDNSSTACK_HOST_IPV4}" example.com AAAA -p "${PDNSSTACK_DNSDIST_DNS_PORT}" +short || true

echo "[INFO] Direct cache-int UDP/TCP"
dig @"${PDNSSTACK_HOST_IPV4}" example.com A -p "${PDNSSTACK_CACHE_INT_DNS_PORT}" +short || true
dig @"${PDNSSTACK_HOST_IPV4}" example.com A -p "${PDNSSTACK_CACHE_INT_DNS_PORT}" +tcp +short || true

if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  echo "[INFO] Direct cache-ngn UDP/TCP"
  dig @"${PDNSSTACK_HOST_IPV4}" flets-west.jp A -p "${PDNSSTACK_CACHE_NGN_DNS_PORT}" +short || true
  dig @"${PDNSSTACK_HOST_IPV4}" flets-west.jp A -p "${PDNSSTACK_CACHE_NGN_DNS_PORT}" +tcp +short || true
fi

echo "[INFO] pdns-auth UDP/TCP"
dig @"${PDNSSTACK_HOST_IPV4}" . SOA -p "${PDNSSTACK_AUTH_DNS_PORT}" +norecurse || true
dig @"${PDNSSTACK_HOST_IPV4}" . SOA -p "${PDNSSTACK_AUTH_DNS_PORT}" +tcp +norecurse || true

echo "[INFO] HTTP endpoints"
curl -sS "http://${PDNSSTACK_HOST_IPV4}:${PDNSSTACK_CACHE_INT_API_PORT}/" >/dev/null || true
curl -sS "http://${PDNSSTACK_HOST_IPV4}:${PDNSSTACK_AUTH_API_PORT}/" >/dev/null || true
curl -sS "http://${PDNSSTACK_HOST_IPV4}:${PDNSSTACK_POWERADMIN_HTTP_PORT}/" >/dev/null || true
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  curl -sS "http://${PDNSSTACK_HOST_IPV4}:${PDNSSTACK_CACHE_NGN_API_PORT}/" >/dev/null || true
fi

echo "[INFO] Healthcheck completed."
