#!/bin/bash

################################################################################
# Docker and Docker Compose Installation Script
# 
# This script installs Docker CE and Docker Compose on Ubuntu/Debian systems.
# It handles:
# - Docker Engine installation from official Docker repository
# - Docker Compose installation (both v1 and v2 plugin)
# - Docker service initialization and startup
# - User group configuration for non-root Docker access
# - Installation verification
#
# Usage: sudo ./install_docker.sh [OPTIONS]
# Options:
#   --compose-version VERSION   Specify Docker Compose v1 version (default: 1.29.2)
#   --skip-compose-v1          Skip Docker Compose v1 installation
#   --user USERNAME            Add specified user to docker group (default: current user)
#   --help                     Display this help message
#
# Author: Generated from shared-fusion-logic-2
# Date: October 21, 2025
################################################################################

set -e  # Exit on error

# Default configuration
DOCKER_COMPOSE_V1_VERSION="1.29.2"
INSTALL_COMPOSE_V1=true
TARGET_USER="${SUDO_USER:-$USER}"
LOG_FILE="docker_install.log"

# Functions for colored output
print_info() {
    echo -e "\033[0;34m[INFO] $1\033[0m"
}

print_success() {
    echo -e "\033[0;32m[SUCCESS] ✓ $1\033[0m"
}

print_error() {
    echo -e "\033[0;31m[ERROR] ✗ $1\033[0m"
}

print_warning() {
    echo -e "\033[0;33m[WARNING] ! $1\033[0m"
}

# Display help message
show_help() {
    cat << EOF
Docker and Docker Compose Installation Script

Usage: sudo ./install_docker.sh [OPTIONS]

Options:
  --compose-version VERSION   Specify Docker Compose v1 version (default: $DOCKER_COMPOSE_V1_VERSION)
  --skip-compose-v1          Skip Docker Compose v1 installation (only install v2 plugin)
  --user USERNAME            Add specified user to docker group (default: $TARGET_USER)
  --help                     Display this help message

Examples:
  sudo ./install_docker.sh
  sudo ./install_docker.sh --compose-version 2.24.0
  sudo ./install_docker.sh --skip-compose-v1
  sudo ./install_docker.sh --user myuser

EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --compose-version)
            DOCKER_COMPOSE_V1_VERSION="$2"
            shift 2
            ;;
        --skip-compose-v1)
            INSTALL_COMPOSE_V1=false
            shift
            ;;
        --user)
            TARGET_USER="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root or with sudo"
   exit 1
fi

# Initialize log file
echo "Docker installation log started at $(date)" > "$LOG_FILE"
print_info "Installation log: $LOG_FILE"

# Detect OS and version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    print_info "Detected OS: $OS $VERSION"
else
    print_error "Cannot detect OS version. /etc/os-release not found."
    exit 1
fi

# Check if OS is supported
case $OS in
    ubuntu|debian)
        print_success "OS is supported: $OS"
        ;;
    *)
        print_warning "This script is designed for Ubuntu/Debian. Detected: $OS"
        print_warning "Installation may not work as expected."
        ;;
esac

################################################################################
# Install Docker Engine
################################################################################
print_info "Checking for Docker installation..."

if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
    print_success "Docker is already installed: $DOCKER_VERSION"
    read -p "Do you want to reinstall Docker? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping Docker installation."
        SKIP_DOCKER=true
    fi
fi

if [[ "$SKIP_DOCKER" != "true" ]]; then
    print_info "Installing Docker Engine..."
    
    # Remove old Docker versions
    print_info "Removing old Docker versions if present..."
    apt-get remove -y docker docker-engine docker.io containerd runc &>> "$LOG_FILE" || true
    
    # Update package index
    print_info "Updating package index..."
    apt-get update &>> "$LOG_FILE"
    
    # Install prerequisites
    print_info "Installing prerequisites..."
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        vim &>> "$LOG_FILE"
    
    print_success "vim installed successfully!"
    
    # Add Docker's official GPG key
    print_info "Adding Docker's official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &>> "$LOG_FILE"
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    print_info "Adding Docker repository..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Update package index again
    print_info "Updating package index with Docker repository..."
    apt-get update &>> "$LOG_FILE"
    
    # Install Docker Engine, CLI, containerd, and plugins
    print_info "Installing Docker Engine and components..."
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin &>> "$LOG_FILE"
    
    print_success "Docker Engine installed successfully!"
    
    # Start and enable Docker service
    print_info "Starting and enabling Docker service..."
    if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
        systemctl enable docker &>> "$LOG_FILE" || true
        systemctl start docker &>> "$LOG_FILE" || true
        print_success "Docker service started and enabled"
    elif command -v service >/dev/null 2>&1; then
        service docker start &>> "$LOG_FILE" || true
        print_success "Docker service started"
    else
        print_warning "No service manager found. You may need to start Docker manually."
    fi
fi

################################################################################
# Install Docker Compose v2 (plugin) - Already installed with docker-compose-plugin
################################################################################
print_info "Verifying Docker Compose v2 (plugin)..."
if docker compose version &>/dev/null; then
    COMPOSE_V2_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    print_success "Docker Compose v2 plugin installed: $COMPOSE_V2_VERSION"
else
    print_warning "Docker Compose v2 plugin not found. It should have been installed with docker-compose-plugin."
    print_info "You can install it manually with: apt-get install docker-compose-plugin"
fi

################################################################################
# Install Docker Compose v1 (standalone binary)
################################################################################
if [[ "$INSTALL_COMPOSE_V1" == "true" ]]; then
    print_info "Checking for Docker Compose v1 (standalone)..."
    
    if command -v docker-compose &>/dev/null; then
        COMPOSE_V1_CURRENT=$(docker-compose --version 2>/dev/null || echo "unknown")
        print_success "Docker Compose v1 is already installed: $COMPOSE_V1_CURRENT"
        read -p "Do you want to reinstall/upgrade Docker Compose v1? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping Docker Compose v1 installation."
            SKIP_COMPOSE_V1=true
        fi
    fi
    
    if [[ "$SKIP_COMPOSE_V1" != "true" ]]; then
        print_info "Installing Docker Compose v1 version $DOCKER_COMPOSE_V1_VERSION..."
        
        # Download Docker Compose
        curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_V1_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose &>> "$LOG_FILE"
        
        # Make it executable
        chmod +x /usr/local/bin/docker-compose
        
        # Create symbolic link (optional, for compatibility)
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true
        
        print_success "Docker Compose v1 ${DOCKER_COMPOSE_V1_VERSION} installed successfully!"
    fi
else
    print_info "Skipping Docker Compose v1 installation (--skip-compose-v1 flag set)"
fi

################################################################################
# Configure Docker user permissions
################################################################################
print_info "Configuring Docker user permissions..."

# Create docker group if it doesn't exist
if ! getent group docker > /dev/null 2>&1; then
    print_info "Creating docker group..."
    groupadd docker &>> "$LOG_FILE"
    print_success "Docker group created"
else
    print_success "Docker group already exists"
fi

# Add user to docker group
if [[ -n "$TARGET_USER" ]] && id "$TARGET_USER" &>/dev/null; then
    if groups "$TARGET_USER" | grep -q '\bdocker\b'; then
        print_success "User '$TARGET_USER' is already in the docker group"
    else
        print_info "Adding user '$TARGET_USER' to docker group..."
        usermod -aG docker "$TARGET_USER" &>> "$LOG_FILE"
        print_success "User '$TARGET_USER' added to docker group"
        print_warning "User '$TARGET_USER' needs to log out and back in for group changes to take effect"
        print_info "Or run: newgrp docker"
    fi
else
    print_warning "User '$TARGET_USER' not found. Skipping user group configuration."
fi

################################################################################
# Verify installation
################################################################################
print_info "Verifying Docker installation..."

# Check Docker version
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    print_success "Docker: $DOCKER_VERSION"
else
    print_error "Docker command not found!"
    exit 1
fi

# Check Docker daemon
if docker info &>/dev/null; then
    print_success "Docker daemon is running"
else
    print_error "Docker daemon is not running or not accessible"
    print_info "Try running: sudo systemctl start docker"
    exit 1
fi

# Check Docker Compose v2
if docker compose version &>/dev/null; then
    COMPOSE_V2_VERSION=$(docker compose version)
    print_success "Docker Compose v2: $COMPOSE_V2_VERSION"
else
    print_warning "Docker Compose v2 not available"
fi

# Check Docker Compose v1
if [[ "$INSTALL_COMPOSE_V1" == "true" ]] && command -v docker-compose &>/dev/null; then
    COMPOSE_V1_VERSION=$(docker-compose --version)
    print_success "Docker Compose v1: $COMPOSE_V1_VERSION"
elif [[ "$INSTALL_COMPOSE_V1" == "true" ]]; then
    print_warning "Docker Compose v1 not found"
fi

# Run hello-world container
print_info "Testing Docker with hello-world container..."
if docker run --rm hello-world &>> "$LOG_FILE"; then
    print_success "Docker hello-world test passed!"
else
    print_error "Docker hello-world test failed. Check $LOG_FILE for details."
    exit 1
fi

################################################################################
# Display summary
################################################################################
echo ""
print_success "═══════════════════════════════════════════════════════════════"
print_success "Docker installation completed successfully!"
print_success "═══════════════════════════════════════════════════════════════"
echo ""
print_info "Installed components:"
echo "  • Docker Engine: $(docker --version | awk '{print $3}' | sed 's/,//')"

if docker compose version &>/dev/null; then
    echo "  • Docker Compose v2 (plugin): $(docker compose version --short)"
fi

if command -v docker-compose &>/dev/null; then
    echo "  • Docker Compose v1 (standalone): $(docker-compose --version | awk '{print $3}' | sed 's/,//')"
fi

echo ""
print_info "Useful Docker commands:"
echo "  • Check Docker status:     docker info"
echo "  • List running containers: docker ps"
echo "  • List all containers:     docker ps -a"
echo "  • List images:             docker images"
echo "  • Run a container:         docker run <image>"
echo "  • Stop a container:        docker stop <container>"
echo "  • Remove a container:      docker rm <container>"
echo ""
print_info "Docker Compose commands:"
echo "  • Using v2 plugin:         docker compose <command>"
echo "  • Using v1 standalone:     docker-compose <command>"
echo ""

if [[ -n "$TARGET_USER" ]] && ! groups "$TARGET_USER" 2>/dev/null | grep -q '\bdocker\b' || [[ "$TARGET_USER" != "$USER" ]]; then
    print_warning "IMPORTANT: User '$TARGET_USER' was added to the docker group."
    print_warning "Please log out and log back in, or run: newgrp docker"
    print_warning "This is required to use Docker without sudo."
fi

echo ""
print_info "Installation log saved to: $LOG_FILE"
print_success "Installation complete! Happy containerizing! 🐳"
echo ""
