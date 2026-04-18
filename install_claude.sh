#!/bin/bash
# =============================================================================
#  install_claude.sh — Standalone Claude Code CLI installer
#
#  Works on: Ubuntu/Debian, Alpine, macOS
#  Usage:    chmod +x install_claude.sh && ./install_claude.sh
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
if command -v claude >/dev/null 2>&1; then
    CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    log_success "Claude Code already installed: ${CURRENT_VERSION}"
    exit 0
fi

# ── Ensure curl is available ──
if ! command -v curl >/dev/null 2>&1; then
    log_info "Installing curl..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq curl
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl
    else
        log_error "Cannot install curl — unsupported package manager"
        exit 1
    fi
fi

# ── Install Claude Code ──
log_info "Installing Claude Code CLI..."
curl -fsSL https://claude.ai/install.sh | bash

# ── Symlink into /usr/local/bin so claude is always in PATH ──
# docker exec uses sh -c which skips profile files, so symlink is the reliable approach
SYMLINKED=false
for p in "$HOME/.local/bin/claude" /root/.local/bin/claude; do
    if [ -f "$p" ] || [ -L "$p" ]; then
        if [ -w /usr/local/bin ]; then
            ln -sf "$p" /usr/local/bin/claude
            log_success "Symlinked $p -> /usr/local/bin/claude"
            SYMLINKED=true
        fi
        break
    fi
done

if [ "$SYMLINKED" = false ]; then
    # Fallback: add to PATH via profile files
    CLAUDE_PATH='export PATH="$HOME/.local/bin:$PATH"'
    for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.ash_profile"; do
        if [ -f "$rc" ] || [ "$rc" = "$HOME/.profile" ]; then
            grep -qF ".local/bin" "$rc" 2>/dev/null || echo "$CLAUDE_PATH" >> "$rc"
        fi
    done
    if [ -w /etc/profile ]; then
        grep -qF ".local/bin" /etc/profile 2>/dev/null || echo "$CLAUDE_PATH" >> /etc/profile
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

# ── Verify ──
if command -v claude >/dev/null 2>&1; then
    log_success "Claude Code installed: $(claude --version 2>/dev/null || echo 'OK')"
    log_info "Location: $(command -v claude)"
else
    log_error "Claude Code binary not found after install"
    log_warn "Try: export PATH=\"\$HOME/.local/bin:\$PATH\""
    exit 1
fi
