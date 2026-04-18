#!/bin/bash
# =============================================================
# FastAPI Service Initialization Script
# =============================================================
# This script handles pre-deployment initialization:
# - Sets default environment variables
# - Creates required directories
# - Sets proper permissions
# - Validates prerequisites
# =============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- Default .env creation ----
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "Creating default .env file..."
  cat > "$SCRIPT_DIR/.env" <<'ENVEOF'
app_name=fastapimicroservices
app_port=4005
http_port=80
NGINX_VERSION=latest
FASTAPI_VERSION=latest
ENVEOF
  echo ".env file created with defaults."
fi

# ---- Directory creation ----
echo "Creating required directories..."
mkdir -p "$SCRIPT_DIR/app"
mkdir -p "$SCRIPT_DIR/nginx"

# ---- Permission setting ----
echo "Setting permissions..."
chmod 755 "$SCRIPT_DIR"
chmod 644 "$SCRIPT_DIR/.env" 2>/dev/null || true

# ---- Prerequisite checks ----
echo "Checking prerequisites..."
if ! command -v docker &> /dev/null; then
  echo "WARNING: docker is not installed or not in PATH."
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  echo "WARNING: docker-compose is not installed or not in PATH."
fi

# ---- Docker-compose file check ----
if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
  echo "WARNING: docker-compose.yml not found in $SCRIPT_DIR"
fi

echo "============================================"
echo "FastAPI initialization complete."
echo "============================================"
