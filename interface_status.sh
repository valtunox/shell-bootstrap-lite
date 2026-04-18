#!/bin/bash
# interface_status.sh - Show all network interfaces, their status, and IPs
# Usage: ./interface_status.sh

if ! command -v ip > /dev/null; then
  echo "'ip' command not found. Please install iproute2."
  exit 1
fi

ip -brief addr

if command -v ethtool > /dev/null; then
  echo
  echo "Detailed link status (requires sudo):"
  for iface in $(ip -o link show | awk -F': ' '{print $2}'); do
    sudo ethtool "$iface" | grep -E 'Link detected|Speed|Duplex' && echo "---"
  done
fi
