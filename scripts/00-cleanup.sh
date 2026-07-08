#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
else
  QUADLET_DIR=/etc/containers/systemd
  SYSTEMD_DIR=/etc/systemd/system
fi

SERVICES=(
  pdnsstack-dnsdist.service
  pdnsstack-cache-int.service
  pdnsstack-cache-ngn.service
  pdnsstack-auth.service
  pdnsstack-db.service
  pdnsstack-poweradmin.service
  pdnsstack-backup.timer
  pdnsstack-backup.service
)
CONTAINERS=(
  pdnsstack-dnsdist
  pdnsstack-cache-int
  pdnsstack-cache-ngn
  pdnsstack-auth
  pdnsstack-db
  pdnsstack-poweradmin
)

echo "[INFO] Stopping services..."
for svc in "${SERVICES[@]}"; do
  systemctl disable --now "${svc}" 2>/dev/null || true
done

echo "[INFO] Removing containers..."
for c in "${CONTAINERS[@]}"; do
  podman rm -f "${c}" 2>/dev/null || true
done

echo "[INFO] Removing Quadlet and systemd files..."
rm -f "${QUADLET_DIR:-/etc/containers/systemd}/pdnsstack-"*.container
rm -f "${QUADLET_DIR:-/etc/containers/systemd}/pdnsstack-net.network"
rm -f "${SYSTEMD_DIR:-/etc/systemd/system}/pdnsstack-backup.service"
rm -f "${SYSTEMD_DIR:-/etc/systemd/system}/pdnsstack-backup.timer"

echo "[INFO] Removing generated repository config..."
find "${REPO_DIR}/config" -type f ! -name ".gitkeep" -delete 2>/dev/null || true
systemctl daemon-reload

echo "[INFO] Cleanup completed. Data and backups were not deleted."
