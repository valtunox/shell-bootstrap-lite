#!/bin/bash
# firewall_rule_check.sh - Check if a port is blocked by local firewall (ufw)
# Usage: ./firewall_rule_check.sh <port>

PORT=$1
if [ -z "$PORT" ]; then
  echo "Usage: $0 <port>"
  exit 1
fi

if ! command -v ufw > /dev/null; then
  echo "ufw is not installed. Please install it with: sudo apt install ufw"
  exit 2
fi

echo "Checking firewall rules for port $PORT..."
ufw status numbered | grep "$PORT" || echo "No explicit rule for port $PORT."
