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

is_valid_port() {
  local port="$1"
  if [[ -z "${port:-}" ]]; then
    return 1
  fi
  if [[ "${port}" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)); then
    return 0
  fi
  return 1
}

is_valid_cidr() {
  local cidr="$1"
  if [[ -z "${cidr:-}" ]]; then
    return 1
  fi
  # basic IPv4 CIDR check: n.n.n.n/NN
  if [[ "${cidr}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(\/([0-9]|[1-2][0-9]|3[0-2]))?$ ]]; then
    return 0
  fi
  return 1
}

add_or_modify_selinux_port() {
  local proto="$1" port="$2" type="$3"
  if [[ -z "${port:-}" ]]; then
    echo "[WARN] empty port; skipping semanage for ${proto}"
    return 0
  fi
  if ! is_valid_port "${port}"; then
    echo "[WARN] non-numeric or out-of-range port '${port}'; skipping semanage for ${proto}"
    return 0
  fi
  if ! command -v semanage >/dev/null 2>&1; then
    echo "[WARN] semanage not found. Skipping ${port}/${proto}."
    return 0
  fi
  semanage port -a -t "${type}" -p "${proto}" "${port}" 2>/dev/null || \
    semanage port -m -t "${type}" -p "${proto}" "${port}" 2>/dev/null || true
}
add_rich_rule() {
  local source="$1" port="$2" proto="$3"
  if [[ -z "${source:-}" || -z "${port:-}" ]]; then
    echo "[WARN] skipping firewall rule with empty source or port: source='${source}' port='${port}'"
    return 0
  fi
  if ! is_valid_cidr "${source}" && [[ ! "${source}" =~ /.+ ]]; then
    echo "[WARN] source '${source}' does not look like CIDR; skipping"
    return 0
  fi
  if ! is_valid_port "${port}"; then
    echo "[WARN] port '${port}' is invalid; skipping"
    return 0
  fi
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
  if is_valid_cidr "${PDNSSTACK_LAN_ALLOWED_CIDR}" && is_valid_port "${PDNSSTACK_DNSDIST_DNS_PORT}"; then
    add_rich_rule "${PDNSSTACK_LAN_ALLOWED_CIDR}" "${PDNSSTACK_DNSDIST_DNS_PORT}" udp
    add_rich_rule "${PDNSSTACK_LAN_ALLOWED_CIDR}" "${PDNSSTACK_DNSDIST_DNS_PORT}" tcp
  else
    echo "[WARN] PDNSSTACK_LAN_ALLOWED_CIDR or PDNSSTACK_DNSDIST_DNS_PORT not set or invalid; skipping LAN rules"
  fi

  if is_valid_cidr "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" && is_valid_port "${PDNSSTACK_CACHE_INT_DNS_PORT}"; then
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_DNS_PORT}" udp
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_DNS_PORT}" tcp
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_INT_API_PORT}" tcp
  else
    echo "[WARN] Zabbix server or cache-int ports not set or invalid; skipping Zabbix rules"
  fi

  if is_valid_cidr "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" && is_valid_port "${PDNSSTACK_AUTH_DNS_PORT}"; then
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_DNS_PORT}" udp
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_DNS_PORT}" tcp
    add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_AUTH_API_PORT}" tcp
  else
    echo "[WARN] Zabbix server or auth ports not set or invalid; skipping auth rules"
  fi

  if [[ "${ENABLE_CACHE_NGN}" == "true" ]]; then
    if is_valid_cidr "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" && is_valid_port "${PDNSSTACK_CACHE_NGN_DNS_PORT}"; then
      add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_DNS_PORT}" udp
      add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_DNS_PORT}" tcp
      add_rich_rule "${PDNSSTACK_ZABBIX_SERVER_IPV4}/32" "${PDNSSTACK_CACHE_NGN_API_PORT}" tcp
    else
      echo "[WARN] Zabbix server or cache-ngn ports not set or invalid; skipping cache-ngn rules"
    fi
  fi

  if is_valid_cidr "${PDNSSTACK_DB_ALLOWED_CIDR}" && is_valid_port "${PDNSSTACK_DB_PORT}"; then
    add_rich_rule "${PDNSSTACK_DB_ALLOWED_CIDR}" "${PDNSSTACK_DB_PORT}" tcp
  else
    echo "[WARN] DB allowed CIDR or DB port not set or invalid; skipping DB rules"
  fi

  if is_valid_cidr "${PDNSSTACK_ADMIN_ALLOWED_CIDR}" && is_valid_port "${PDNSSTACK_POWERADMIN_HTTP_PORT}"; then
    add_rich_rule "${PDNSSTACK_ADMIN_ALLOWED_CIDR}" "${PDNSSTACK_POWERADMIN_HTTP_PORT}" tcp
  else
    echo "[WARN] Admin allowed CIDR or PowerAdmin port not set or invalid; skipping admin rules"
  fi

  firewall-cmd --reload
else
  echo "[WARN] firewalld is not available or not running."
fi

echo "[INFO] Security preparation completed."
