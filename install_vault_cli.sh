#!/usr/bin/env bash
# install_vault_cli.sh - Install only the Vault CLI (no server, no Kubernetes)
set -euo pipefail

VAULT_VERSION="${VAULT_VERSION:-1.15.2}"
VAULT_BIN_PATH="${VAULT_BIN_PATH:-/usr/local/bin/vault}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}INFO:${NC} $1"; }
ok(){ echo -e "${GREEN}OK:${NC} $1"; }
err(){ echo -e "${RED}ERROR:${NC} $1" >&2; }

usage(){
  cat <<EOF
Install Vault CLI only

Usage: $0 [options]

Options:
  -v, --version <ver>     Vault CLI version (default: ${VAULT_VERSION})
  -b, --bin <path>        Install path (default: ${VAULT_BIN_PATH})
  -h, --help              Show this help
EOF
}

parse_args(){
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--version) VAULT_VERSION="$2"; shift 2;;
      -b|--bin) VAULT_BIN_PATH="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) err "Unknown option: $1"; usage; exit 1;;
    esac
  done
}

need_root(){
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

command_exists(){ command -v "$1" >/dev/null 2>&1; }

install_cli(){
  info "Installing Vault CLI ${VAULT_VERSION} to ${VAULT_BIN_PATH}"
  local os="linux" arch="amd64"
  case "$(uname -m)" in
    x86_64) arch="amd64";;
    aarch64|arm64) arch="arm64";;
    armv7l|armv6l) arch="arm";;
  esac
  local url="https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_${os}_${arch}.zip"
  local tmpdir; tmpdir="$(mktemp -d)"
  if ! command_exists curl; then $SUDO apt-get update -y >/dev/null 2>&1 || true; $SUDO apt-get install -y curl >/dev/null 2>&1 || true; fi
  if ! command_exists unzip; then $SUDO apt-get install -y unzip >/dev/null 2>&1 || true; fi
  curl -fsSL -o "${tmpdir}/vault.zip" "$url" || { err "Failed to download $url"; exit 1; }
  unzip -q -o "${tmpdir}/vault.zip" -d "$tmpdir" || { err "Failed to unzip"; exit 1; }
  $SUDO install -m 0755 -D "${tmpdir}/vault" "$VAULT_BIN_PATH"
  rm -rf "$tmpdir"
  ok "Vault CLI installed"
}

main(){
  parse_args "$@"
  need_root
  install_cli
  echo
  echo "Try it:"
  echo "  vault version"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
