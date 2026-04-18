#!/bin/bash
# =============================================================================
#  install_codex.sh — Standalone OpenAI Codex CLI installer
#
#  Works on: Ubuntu/Debian, Alpine, macOS
#  Usage:    chmod +x install_codex.sh && ./install_codex.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ── Check if already installed ──
if command -v codex >/dev/null 2>&1; then
    log_success "OpenAI Codex already installed"
    exit 0
fi

# ── Ensure Node.js + npm are available ──
if ! command -v node >/dev/null 2>&1; then
    log_info "Node.js not found — installing..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache nodejs npm
    elif command -v yum >/dev/null 2>&1; then
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        yum install -y nodejs
    else
        log_error "Cannot install Node.js — unsupported package manager"
        exit 1
    fi
    log_success "Node.js installed: $(node --version)"
fi

if ! command -v npm >/dev/null 2>&1; then
    log_error "npm not found — cannot install Codex"
    exit 1
fi

# ── Install OpenAI Codex CLI ──
log_info "Installing OpenAI Codex CLI..."
npm install -g @openai/codex

# ── Verify ──
if command -v codex >/dev/null 2>&1; then
    log_success "OpenAI Codex installed"
    log_info "Location: $(command -v codex)"
else
    log_error "Codex binary not found after install"
    log_warn "Check that npm global bin is in your PATH"
    exit 1
fi
