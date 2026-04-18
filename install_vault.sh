#!/usr/bin/env bash

# install_vault.sh
# Local installer for HashiCorp Vault (no Kubernetes/Helm). Sets up binary, config, and optional systemd service.

set -euo pipefail

# Defaults (can be overridden by env or flags)
VAULT_VERSION="${VAULT_VERSION:-1.15.2}"
VAULT_USER="${VAULT_USER:-vault}"
VAULT_GROUP="${VAULT_GROUP:-vault}"
VAULT_DATA_DIR="${VAULT_DATA_DIR:-/var/lib/vault}"
VAULT_CONFIG_DIR="${VAULT_CONFIG_DIR:-/etc/vault.d}"
VAULT_BIN_PATH="${VAULT_BIN_PATH:-/usr/local/bin/vault}"
VAULT_SERVICE_NAME="${VAULT_SERVICE_NAME:-vault}"
SETUP_SYSTEMD="${SETUP_SYSTEMD:-true}"   # true/false
SETUP_DEV_MODE="${SETUP_DEV_MODE:-false}" # true/false - if true, run Vault in -dev mode (for local dev only)
DEV_ROOT_TOKEN="${DEV_ROOT_TOKEN:-dev-only-token}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"; }
info() { echo -e "${BLUE}INFO:${NC} $1"; }
warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
ok() { echo -e "${GREEN}OK:${NC} $1"; }
err() { echo -e "${RED}ERROR:${NC} $1" >&2; }

need_root() {
  if [[ $(id -u) -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      export SUDO=sudo
    else
      err "This script needs root privileges. Run as root or install sudo."; exit 1
    fi
  else
    export SUDO=
  fi
}

usage() {
  cat <<EOF
Local Vault Installer (no Kubernetes)

Usage: $0 [options]

Options:
  -v, --version <ver>     Vault version to install (default: ${VAULT_VERSION})
  -b, --bin <path>        Install path for vault binary (default: ${VAULT_BIN_PATH})
  -d, --data-dir <dir>    Data dir (default: ${VAULT_DATA_DIR})
  -c, --config-dir <dir>  Config dir (default: ${VAULT_CONFIG_DIR})
  -u, --user <name>       User to run vault (default: ${VAULT_USER})
  -g, --group <name>      Group to run vault (default: ${VAULT_GROUP})
  --dev                   Run Vault in development mode (NOT for production)
  --dev-root-token-id <tok>  Dev-mode root token id (default: ${DEV_ROOT_TOKEN})
  --no-systemd            Do not create/enable systemd service
  -h, --help              Show this help

Notes:
  - This installs the Vault binary and (optionally) a systemd service using file storage.
  - TLS is disabled in the default config. Enable TLS for production.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version) VAULT_VERSION="$2"; shift 2;;
      -b|--bin) VAULT_BIN_PATH="$2"; shift 2;;
      -d|--data-dir) VAULT_DATA_DIR="$2"; shift 2;;
      -c|--config-dir) VAULT_CONFIG_DIR="$2"; shift 2;;
      -u|--user) VAULT_USER="$2"; shift 2;;
      -g|--group) VAULT_GROUP="$2"; shift 2;;
  --dev) SETUP_DEV_MODE="true"; shift;;
    --dev-root-token) DEV_ROOT_TOKEN="$2"; shift 2;;
    --dev-root-token-id) DEV_ROOT_TOKEN="$2"; shift 2;;
      --no-systemd) SETUP_SYSTEMD="false"; shift;;
      -h|--help) usage; exit 0;;
      *) err "Unknown option: $1"; usage; exit 1;;
    esac
  done
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

install_vault_binary() {
  info "Installing Vault ${VAULT_VERSION} to ${VAULT_BIN_PATH}"

  local os="linux" arch="amd64"
  case "$(uname -m)" in
    x86_64) arch="amd64";;
    aarch64|arm64) arch="arm64";;
    armv7l|armv6l) arch="arm";;
  esac

  local url="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${os}_${arch}.zip"
  local tmpdir
  tmpdir="$(mktemp -d)"

  if ! command_exists curl; then $SUDO apt-get update -y >/dev/null 2>&1 || true; $SUDO apt-get install -y curl >/dev/null 2>&1 || true; fi
  if ! command_exists unzip; then $SUDO apt-get install -y unzip >/dev/null 2>&1 || true; fi

  curl -fsSL -o "${tmpdir}/vault.zip" "$url" || { err "Failed to download $url"; exit 1; }
  unzip -q -o "${tmpdir}/vault.zip" -d "$tmpdir" || { err "Failed to unzip vault"; exit 1; }

  $SUDO install -m 0755 -D "${tmpdir}/vault" "$VAULT_BIN_PATH"
  rm -rf "$tmpdir"
  ok "Vault binary installed"
}

ensure_user_group() {
  if ! id -u "$VAULT_USER" >/dev/null 2>&1; then
    info "Creating user $VAULT_USER"
    $SUDO useradd --system --home "$VAULT_DATA_DIR" --shell /usr/sbin/nologin "$VAULT_USER" || true
  fi
  if ! getent group "$VAULT_GROUP" >/dev/null 2>&1; then
    info "Creating group $VAULT_GROUP"
    $SUDO groupadd --system "$VAULT_GROUP" || true
  fi
  $SUDO usermod -a -G "$VAULT_GROUP" "$VAULT_USER" >/dev/null 2>&1 || true
}

prepare_dirs() {
  $SUDO mkdir -p "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"
  $SUDO chown -R "$VAULT_USER":"$VAULT_GROUP" "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"
  $SUDO chmod 750 "$VAULT_DATA_DIR" "$VAULT_CONFIG_DIR"
}

write_default_config() {
  local cfg="$VAULT_CONFIG_DIR/vault.hcl"
  if [[ -f "$cfg" ]]; then
    warn "Config already exists at $cfg, leaving as-is"
    return
  fi
  info "Writing default config to $cfg"
  cat <<EOF | $SUDO tee "$cfg" >/dev/null
ui = true
disable_mlock = true

storage "file" {
  path = "${VAULT_DATA_DIR}"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable   = 1
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF
  $SUDO chown "$VAULT_USER":"$VAULT_GROUP" "$cfg"
  $SUDO chmod 640 "$cfg"
}

write_systemd_unit() {
  if [[ "$SETUP_SYSTEMD" != "true" ]]; then
    info "Skipping systemd setup (--no-systemd)"
    return
  fi
  local unit="/etc/systemd/system/${VAULT_SERVICE_NAME}.service"
  if [[ -f "$unit" ]]; then
    warn "Systemd unit already exists at $unit, leaving as-is"
    return
  fi
  local exec_start="${VAULT_BIN_PATH} server -config=${VAULT_CONFIG_DIR}"
  if [[ "${SETUP_DEV_MODE}" == "true" ]]; then
    exec_start="${VAULT_BIN_PATH} server -dev -dev-root-token-id=${DEV_ROOT_TOKEN} -dev-listen-address=0.0.0.0:8200"
  fi

  cat <<EOF | $SUDO tee "$unit" >/dev/null
[Unit]
Description=HashiCorp Vault - A tool for managing secrets
Documentation=https://www.vaultproject.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
User=${VAULT_USER}
Group=${VAULT_GROUP}
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=${exec_start}
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=3
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF
}

enable_and_start() {
  if [[ "$SETUP_SYSTEMD" != "true" ]]; then return; fi
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now "$VAULT_SERVICE_NAME"
  ok "Vault service enabled and started"
}

post_install_message() {
  echo
  echo "========================================="
  echo "Vault Installed"
  echo "========================================="
  echo "Binary:    $VAULT_BIN_PATH"
  echo "Config:    $VAULT_CONFIG_DIR/vault.hcl"
  echo "Data Dir:  $VAULT_DATA_DIR"
  if [[ "$SETUP_SYSTEMD" == "true" ]]; then
    echo "Service:   systemctl status $VAULT_SERVICE_NAME"
  else
    echo "Run manually: $VAULT_BIN_PATH server -config=$VAULT_CONFIG_DIR"
  fi
  if [[ "${SETUP_DEV_MODE}" == "true" ]]; then
    echo
    echo "*** Dev mode enabled: Vault is running in -dev with a fixed root token"
    echo "Dev root token (insecure, for local dev only): ${DEV_ROOT_TOKEN}"
    echo "DO NOT use -dev mode in production. The dev token is predictable and unsealed storage is insecure."
  fi
  echo
  echo "Next steps (first time only):"
  echo "  export VAULT_ADDR=http://127.0.0.1:8200"
  echo "  vault operator init > ~/vault_init.txt"
  echo "  vault operator unseal <key>  (repeat 3 times with different keys)"
  echo "  vault login <root_token>"
}

main() {
  parse_args "$@"
  need_root
  info "Starting local Vault installation (no Kubernetes)"
  install_vault_binary
  ensure_user_group
  prepare_dirs
  write_default_config
  write_systemd_unit
  enable_and_start
  post_install_message
  ok "Installation complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
