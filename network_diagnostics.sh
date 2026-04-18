#!/bin/bash
# network_diagnostics.sh - Production-grade network diagnostics for Ubuntu
# Usage: ./network_diagnostics.sh <host> <port>

HOST=$1
PORT=$2

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <host> <port>"
  exit 1
fi

set -e

# Detect OS for ping flag
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
  PING_COUNT_FLAG="-n"
else
  PING_COUNT_FLAG="-c"
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting network diagnostics for $HOST:$PORT"

# 1. DNS resolution
log "Checking DNS resolution..."
if command -v getent > /dev/null 2>&1; then
  if getent hosts "$HOST" > /dev/null 2>&1; then
    log "DNS resolution successful: $(getent hosts "$HOST" | awk '{print $1}')"
  else
    log "DNS resolution failed for $HOST"
    exit 2
  fi
elif command -v nslookup > /dev/null 2>&1; then
  if nslookup "$HOST" > /dev/null 2>&1; then
    log "DNS resolution successful (nslookup)"
  else
    log "DNS resolution failed for $HOST"
    exit 2
  fi
else
  log "No DNS lookup tool available. Skipping."
fi

# 2. Ping test
log "Pinging $HOST..."
if ping $PING_COUNT_FLAG 3 "$HOST" > /dev/null 2>&1; then
  log "Ping to $HOST successful."
else
  log "Ping to $HOST failed."
fi

# 3. Traceroute
log "Running traceroute to $HOST..."
if command -v traceroute > /dev/null; then
  traceroute "$HOST"
else
  log "traceroute not installed. Skipping."
fi

# 4. Port check
log "Checking port $PORT on $HOST..."
if command -v nc > /dev/null 2>&1; then
  if nc -zvw3 "$HOST" "$PORT" 2>&1; then
    log "Port $PORT is open on $HOST."
  else
    log "Port $PORT is closed on $HOST."
  fi
elif timeout 3 bash -c "echo >/dev/tcp/$HOST/$PORT" 2>/dev/null; then
  log "Port $PORT is open on $HOST."
else
  log "Port $PORT is closed on $HOST."
fi

# 5. Service scan (optional, requires nmap)
if command -v nmap > /dev/null; then
  log "Running nmap service scan on $HOST:$PORT..."
  nmap -p "$PORT" -sV "$HOST"
else
  log "nmap not installed. Skipping service scan."
fi

log "Network diagnostics completed."
