#!/bin/bash
# dns_health_check.sh - Check DNS server health and response time
# Usage: ./dns_health_check.sh <dns_server> [domain]

DNS_SERVER=$1
DOMAIN=${2:-google.com}

if [ -z "$DNS_SERVER" ]; then
  echo "Usage: $0 <dns_server> [domain]"
  exit 1
fi

if ! command -v dig > /dev/null; then
  echo "dig is not installed. Please install it with: sudo apt install dnsutils"
  exit 2
fi

echo "Querying $DOMAIN using DNS server $DNS_SERVER..."
dig @$DNS_SERVER $DOMAIN +stats +time=2
