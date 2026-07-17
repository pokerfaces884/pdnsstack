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
if [[ "$(id -u)" -ne 0 ]]; then echo "[ERROR] Run as root."; exit 1; fi

add_or_modify_selinux_port() {
  local proto="$1" port="$2" type="$3"
  if ! command -v semanage >/dev/null 2>&1; then
    echo "[WARN] semanage not found. Skipping ${port}/${proto}."
    return 0
  fi
  semanage port -a -t "${type}" -p "${proto}" "${port}" 2>/dev/null || \
    semanage port -m -t "${type}" -p "${proto}" "${port}" 2>/dev/null || true
}
add_rich_rule() {
  local source="$1" port="$2" proto="$3"
  firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"${source}\" port port=\"${port}\" protocol=\"${proto}\" accept" >/dev/null
}

if command -v restorecon >/dev/null 2>&1; then
  if command -v semanage >/dev/null 2>&1; then
    semanage fcontext -a -t container_file_t "${PDNSSTACK_BASE_DIR}(/.*)?" 2>/dev/null || true
  fi
  restorecon -Rv "${PDNSSTACK_BASE_DIR}" || true
fi

# SELinux port labels
for p in "${PDNSSTACK_DNSDIST_DNS_PORT}" "${PDNSSTACK_CACHE_INT_DNS_PORT}" "${PDNSSTACK_AUTH_DNS_PORT}"; do
  add_or_modify_selinux_port udp "${p}" dns_port_t
  add_or_modify_selinux_port tcp "${p}" dns_port_t
done
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  add_or_modify_selinux_port udp "${PDNSSTACK_CACHE_NGN_DNS_PORT}" dns_port_t
  add_or_modify_selinux_port tcp "${PDNSSTACK_CACHE_NGN_DNS_PORT}" dns_port_t
fi
for p in "${PDNSSTACK_CACHE_INT_API_PORT}" "${PDNSSTACK_AUTH_API_PORT}" "${PDNSSTACK_POWERADMIN_HTTP_PORT}"; do
  add_or_modify_selinux_port tcp "${p}" http_port_t
done
if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
  add_or_modify_selinux_port tcp "${PDNSSTACK_CACHE_NGN_API_PORT}" http_port_t
fi
add_or_modify_selinux_port tcp "${PDNSSTACK_DB_PORT}" mysqld_port_t

# firewalld rich rules
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  add_rich_rule "${LAN_ALLOWED_CIDR}" "${PDNSSTACK_DNSDIST_DNS_PORT}" udp
  add_rich_rule "${LAN_ALLOWED_CIDR}" "${PDNSSTACK_DNSDIST_DNS_PORT}" tcp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_DNS_PORT}" udp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_DNS_PORT}" tcp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_API_PORT}" tcp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_DNS_PORT}" udp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_DNS_PORT}" tcp
  add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_API_PORT}" tcp
  if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
    add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_DNS_PORT}" udp
    add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_DNS_PORT}" tcp
    add_rich_rule "${ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_API_PORT}" tcp
  fi
  add_rich_rule "${DB_ALLOWED_CIDR}" "${PDNSSTACK_DB_PORT}" tcp
  add_rich_rule "${ADMIN_ALLOWED_CIDR}" "${PDNSSTACK_POWERADMIN_HTTP_PORT}" tcp
  firewall-cmd --reload
else
  echo "[WARN] firewalld is not available or not running."
fi

echo "[INFO] Security preparation completed."
