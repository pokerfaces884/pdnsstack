#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_DIR}/.env"
RUNTIME_FILE="${REPO_DIR}/config/runtime.env"
TEMPLATE_DIR="${REPO_DIR}/template"
CONFIG_DIR="${REPO_DIR}/config"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[ERROR] .env file not found: ${ENV_FILE}"
  echo "        Please copy .env.sample to .env and edit it."
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

# ---------------------------------------------------------
# Validate module prefix
# ---------------------------------------------------------

if [[ -z "${PDNSSTACK_MODULE_PREFIX:-}" ]]; then
  echo "[ERROR] Required variable is empty: PDNSSTACK_MODULE_PREFIX"
  exit 1
fi

if ! [[ "${PDNSSTACK_MODULE_PREFIX}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "[ERROR] Invalid PDNSSTACK_MODULE_PREFIX: ${PDNSSTACK_MODULE_PREFIX}"
  echo "        Allowed pattern: ^[A-Za-z0-9][A-Za-z0-9_-]*$"
  exit 1
fi

# ---------------------------------------------------------
# Generate resource names from PDNSSTACK_MODULE_PREFIX
# ---------------------------------------------------------

PDNSSTACK_NETWORK_NAME="${PDNSSTACK_MODULE_PREFIX}-net"
PDNSSTACK_DNSDIST_NAME="${PDNSSTACK_MODULE_PREFIX}-dnsdist"
PDNSSTACK_CACHE_INT_NAME="${PDNSSTACK_MODULE_PREFIX}-cache-int"
PDNSSTACK_CACHE_NGN_NAME="${PDNSSTACK_MODULE_PREFIX}-cache-ngn"
PDNSSTACK_AUTH_NAME="${PDNSSTACK_MODULE_PREFIX}-auth"
PDNSSTACK_DB_NAME="${PDNSSTACK_MODULE_PREFIX}-db"
PDNSSTACK_POWERADMIN_NAME="${PDNSSTACK_MODULE_PREFIX}-poweradmin"
PDNSSTACK_BACKUP_NAME="${PDNSSTACK_MODULE_PREFIX}-backup"

PDNSSTACK_NETWORK_SERVICE="${PDNSSTACK_NETWORK_NAME}-network.service"
PDNSSTACK_DNSDIST_SERVICE="${PDNSSTACK_DNSDIST_NAME}.service"
PDNSSTACK_CACHE_INT_SERVICE="${PDNSSTACK_CACHE_INT_NAME}.service"
PDNSSTACK_CACHE_NGN_SERVICE="${PDNSSTACK_CACHE_NGN_NAME}.service"
PDNSSTACK_AUTH_SERVICE="${PDNSSTACK_AUTH_NAME}.service"
PDNSSTACK_DB_SERVICE="${PDNSSTACK_DB_NAME}.service"
PDNSSTACK_POWERADMIN_SERVICE="${PDNSSTACK_POWERADMIN_NAME}.service"
PDNSSTACK_BACKUP_SERVICE="${PDNSSTACK_BACKUP_NAME}.service"
PDNSSTACK_BACKUP_TIMER="${PDNSSTACK_BACKUP_NAME}.timer"

export PDNSSTACK_NETWORK_NAME
export PDNSSTACK_DNSDIST_NAME
export PDNSSTACK_CACHE_INT_NAME
export PDNSSTACK_CACHE_NGN_NAME
export PDNSSTACK_AUTH_NAME
export PDNSSTACK_DB_NAME
export PDNSSTACK_POWERADMIN_NAME
export PDNSSTACK_BACKUP_NAME

export PDNSSTACK_NETWORK_SERVICE
export PDNSSTACK_DNSDIST_SERVICE
export PDNSSTACK_CACHE_INT_SERVICE
export PDNSSTACK_CACHE_NGN_SERVICE
export PDNSSTACK_AUTH_SERVICE
export PDNSSTACK_DB_SERVICE
export PDNSSTACK_POWERADMIN_SERVICE
export PDNSSTACK_BACKUP_SERVICE
export PDNSSTACK_BACKUP_TIMER

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

# ---------------------------------------------------------
# Generate optional secrets
# ---------------------------------------------------------

# 20 hex characters, avoids pipe/SIGPIPE issues under set -euo pipefail.
generate_secret_20() {
  openssl rand -hex 10
}

optional_secret_vars=(
  PDNSSTACK_AUTH_API_KEY
  PDNSSTACK_RECURSOR_API_KEY
  PDNSSTACK_DNSDIST_API_KEY
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
      printf '\n%s=%s\n' "${var}" "${value}" >> "${ENV_FILE}"
    fi

    updated_env=true
    echo "[INFO] Auto-generated ${var} and wrote it to .env"
  fi
done

if [[ "${updated_env}" == "true" ]]; then
  chmod 600 "${ENV_FILE}" || true
fi

# ---------------------------------------------------------
# Validate initial domain
# ---------------------------------------------------------

if ! [[ "${PDNSSTACK_INITIAL_DOMAIN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "[ERROR] Invalid PDNSSTACK_INITIAL_DOMAIN: ${PDNSSTACK_INITIAL_DOMAIN}"
  echo "        Allowed characters: A-Z a-z 0-9 dot hyphen"
  exit 1
fi

# ---------------------------------------------------------
# Determine runtime flags
# ---------------------------------------------------------

# If both NGN DNS IPv6 forwarders are empty, cache-ngn is disabled.
if [[ -n "${PDNSSTACK_NGN_DNS_IPV6_1:-}" || -n "${PDNSSTACK_NGN_DNS_IPV6_2:-}" ]]; then
  ENABLE_CACHE_NGN=true
else
  ENABLE_CACHE_NGN=false
fi
export ENABLE_CACHE_NGN

# ---------------------------------------------------------
# Generate runtime.env for deploy/startup/cleanup scripts
# ---------------------------------------------------------

mkdir -p "${CONFIG_DIR}"

cat > "${RUNTIME_FILE}" <<EOF
# Generated by scripts/01-create.sh
# Do not edit manually unless you understand the deployment flow.

ENABLE_CACHE_NGN=${ENABLE_CACHE_NGN}

PDNSSTACK_NETWORK_NAME=${PDNSSTACK_NETWORK_NAME}
PDNSSTACK_DNSDIST_NAME=${PDNSSTACK_DNSDIST_NAME}
PDNSSTACK_CACHE_INT_NAME=${PDNSSTACK_CACHE_INT_NAME}
PDNSSTACK_CACHE_NGN_NAME=${PDNSSTACK_CACHE_NGN_NAME}
PDNSSTACK_AUTH_NAME=${PDNSSTACK_AUTH_NAME}
PDNSSTACK_DB_NAME=${PDNSSTACK_DB_NAME}
PDNSSTACK_POWERADMIN_NAME=${PDNSSTACK_POWERADMIN_NAME}
PDNSSTACK_BACKUP_NAME=${PDNSSTACK_BACKUP_NAME}

PDNSSTACK_NETWORK_SERVICE=${PDNSSTACK_NETWORK_SERVICE}
PDNSSTACK_DNSDIST_SERVICE=${PDNSSTACK_DNSDIST_SERVICE}
PDNSSTACK_CACHE_INT_SERVICE=${PDNSSTACK_CACHE_INT_SERVICE}
PDNSSTACK_CACHE_NGN_SERVICE=${PDNSSTACK_CACHE_NGN_SERVICE}
PDNSSTACK_AUTH_SERVICE=${PDNSSTACK_AUTH_SERVICE}
PDNSSTACK_DB_SERVICE=${PDNSSTACK_DB_SERVICE}
PDNSSTACK_POWERADMIN_SERVICE=${PDNSSTACK_POWERADMIN_SERVICE}
PDNSSTACK_BACKUP_SERVICE=${PDNSSTACK_BACKUP_SERVICE}
PDNSSTACK_BACKUP_TIMER=${PDNSSTACK_BACKUP_TIMER}
EOF

chmod 644 "${RUNTIME_FILE}" || true

# ---------------------------------------------------------
# Generate config files from templates
# ---------------------------------------------------------

pdnsstack_render_templates() {
  if [[ ! -d "${TEMPLATE_DIR}" ]]; then
    echo "[ERROR] Template directory not found: ${TEMPLATE_DIR}"
    exit 1
  fi

  python3 - "${TEMPLATE_DIR}" "${CONFIG_DIR}" <<'PY_RENDER'
import os
import re
import shutil
import sys
from pathlib import Path

template_dir = Path(sys.argv[1])
config_dir = Path(sys.argv[2])

prefix = os.environ["PDNSSTACK_MODULE_PREFIX"]

generated_dirs = [
    "auth",
    "cache-int",
    "cache-ngn",
    "db",
    "dnsdist",
    "poweradmin",
    "quadlet",
    "systemd",
]

for name in generated_dirs:
    target = config_dir / name
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)

def render_text(text: str) -> str:
    # Jinja-like placeholders: {{ VAR_NAME }}
    def repl_jinja(match: re.Match) -> str:
        key = match.group(1)
        return os.environ.get(key, match.group(0))

    text = re.sub(r"\{\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}\}", repl_jinja, text)

    # Env-style placeholders: ${VAR_NAME}
    def repl_env(match: re.Match) -> str:
        key = match.group(1)
        return os.environ.get(key, match.group(0))

    text = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", repl_env, text)

    # Backward compatibility for old hard-coded default prefix.
    if prefix != "pdnsstack":
        text = text.replace("pdnsstack-", f"{prefix}-")

    return text

def render_path_part(name: str) -> str:
    rendered = render_text(name)

    if rendered.endswith(".j2"):
        rendered = rendered[:-3]
    elif rendered.endswith(".jinja"):
        rendered = rendered[:-6]

    if prefix != "pdnsstack" and rendered.startswith("pdnsstack-"):
        rendered = f"{prefix}-" + rendered[len("pdnsstack-"):]

    return rendered

for src in template_dir.rglob("*"):
    rel = src.relative_to(template_dir)
    rendered_parts = [render_path_part(part) for part in rel.parts]
    dst = config_dir.joinpath(*rendered_parts)

    if src.is_dir():
        dst.mkdir(parents=True, exist_ok=True)
        continue

    dst.parent.mkdir(parents=True, exist_ok=True)

    try:
        raw = src.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        shutil.copy2(src, dst)
        continue

    dst.write_text(render_text(raw), encoding="utf-8")

print(f"[INFO] rendered templates from {template_dir} to {config_dir}")
PY_RENDER
}

pdnsstack_render_templates

# ---------------------------------------------------------
# Validate generated files
# ---------------------------------------------------------

pdnsstack_validate_generated_files() {
  local required_files=(
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_NETWORK_NAME}.network"
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_DNSDIST_NAME}.container"
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_CACHE_INT_NAME}.container"
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_AUTH_NAME}.container"
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_DB_NAME}.container"
    "${CONFIG_DIR}/quadlet/${PDNSSTACK_POWERADMIN_NAME}.container"
    "${CONFIG_DIR}/systemd/${PDNSSTACK_BACKUP_NAME}.service"
    "${CONFIG_DIR}/systemd/${PDNSSTACK_BACKUP_NAME}.timer"
    "${CONFIG_DIR}/db/init.sql"
    "${CONFIG_DIR}/poweradmin/config.inc.php"
    "${CONFIG_DIR}/cache-int/recursor.yml"
  )

  if [[ "${ENABLE_CACHE_NGN:-false}" == "true" ]]; then
    required_files+=(
      "${CONFIG_DIR}/quadlet/${PDNSSTACK_CACHE_NGN_NAME}.container"
      "${CONFIG_DIR}/cache-ngn/recursor.yml"
    )
  fi

  for file in "${required_files[@]}"; do
    if [[ ! -f "${file}" ]]; then
      echo "[ERROR] Required generated file not found: ${file}"
      exit 1
    fi
  done

  echo "[INFO] Generated file validation completed."
}

pdnsstack_validate_generated_files

# ---------------------------------------------------------
# Generate PowerDNS Recursor forwarder settings
# ---------------------------------------------------------

# NOTE:
# - Do not modify incoming.listen here.
# - listen is the local/container-side bind address.
# - PDNSSTACK_UPSTREAM_DNS_* and PDNSSTACK_NGN_DNS_* are upstream forwarders.

pdnsstack_upsert_recursor_forwarders() {
  local file="$1"
  local mode="$2"

  if [[ ! -f "${file}" ]]; then
    echo "[WARN] recursor config not found: ${file}"
    return 0
  fi

  python3 - "${file}" "${mode}" <<'PY_FORWARDERS'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode = sys.argv[2]

text = path.read_text()
lines = text.splitlines()

if mode == "cache-int":
    forwarders = [
        os.environ.get("PDNSSTACK_UPSTREAM_DNS_IPV4_1", ""),
        os.environ.get("PDNSSTACK_UPSTREAM_DNS_IPV4_2", ""),
        os.environ.get("PDNSSTACK_UPSTREAM_DNS_IPV6_1", ""),
        os.environ.get("PDNSSTACK_UPSTREAM_DNS_IPV6_2", ""),
    ]
elif mode == "cache-ngn":
    forwarders = [
        os.environ.get("PDNSSTACK_NGN_DNS_IPV6_1", ""),
        os.environ.get("PDNSSTACK_NGN_DNS_IPV6_2", ""),
    ]
else:
    raise SystemExit(f"unknown mode: {mode}")

forwarders = [v.strip() for v in forwarders if v.strip()]

if not forwarders:
    print(f"[WARN] no forwarders configured for {mode}; forward_zones_recurse will not be written")
    path.write_text("\n".join(lines) + "\n")
    raise SystemExit(0)

def is_top_level(line: str) -> bool:
    return line and not line.startswith((" ", "\t")) and line.rstrip().endswith(":")

# Remove existing recursor.forward_zones_recurse block if present.
new_lines = []
i = 0
inside_recursor = False

while i < len(lines):
    line = lines[i]

    if line == "recursor:":
        inside_recursor = True
        new_lines.append(line)
        i += 1
        continue

    if inside_recursor and is_top_level(line):
        inside_recursor = False

    if inside_recursor and line.startswith("  forward_zones_recurse:"):
        # Skip this block until next recursor child at indent 2 or next top-level section.
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if is_top_level(nxt):
                inside_recursor = False
                break
            if nxt.startswith("  ") and not nxt.startswith("    ") and nxt.strip():
                break
            i += 1
        continue

    new_lines.append(line)
    i += 1

lines = new_lines

forward_block = [
    "  forward_zones_recurse:",
    '    - zone: "."',
    "      forwarders:",
]

for f in forwarders:
    forward_block.append(f'        - "{f}"')

if "recursor:" in lines:
    idx = lines.index("recursor:")
    insert_at = idx + 1
    lines[insert_at:insert_at] = forward_block
else:
    if lines and lines[-1].strip():
        lines.append("")
    lines.append("recursor:")
    lines.extend(forward_block)

path.write_text("\n".join(lines) + "\n")
print(f"[INFO] updated forward_zones_recurse in {path} for {mode}")
PY_FORWARDERS
}

pdnsstack_generate_recursor_forwarders() {
  pdnsstack_upsert_recursor_forwarders "${CONFIG_DIR}/cache-int/recursor.yml" "cache-int"

  if [[ "${ENABLE_CACHE_NGN:-false}" == "true" ]]; then
    pdnsstack_upsert_recursor_forwarders "${CONFIG_DIR}/cache-ngn/recursor.yml" "cache-ngn"
  else
    echo "[INFO] cache-ngn disabled; skip cache-ngn forwarder generation"
  fi
}

pdnsstack_generate_recursor_forwarders

echo "[INFO] Environment validation completed."
echo "[INFO] Initial domain: ${PDNSSTACK_INITIAL_DOMAIN}"
echo "[INFO] Host IPv4: ${PDNSSTACK_HOST_IPV4}"
echo "[INFO] Module prefix: ${PDNSSTACK_MODULE_PREFIX}"
echo "[INFO] Network name: ${PDNSSTACK_NETWORK_NAME}"
echo "[INFO] DB container name: ${PDNSSTACK_DB_NAME}"
echo "[INFO] ENABLE_CACHE_NGN=${ENABLE_CACHE_NGN}"
echo "[INFO] Generated runtime file: ${RUNTIME_FILE}"
echo "[INFO] Generated config directory: ${CONFIG_DIR}"