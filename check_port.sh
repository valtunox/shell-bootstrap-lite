#!/bin/bash

# Usage: ./check_port.sh <host> <port>

HOST=$1
PORT=$2

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <host> <port>"
  exit 1
fi

echo "Checking port $PORT on host $HOST..."
if nc -zv "$HOST" "$PORT"; then
  echo "Port $PORT is open on $HOST."
else
  echo "Port $PORT is closed on $HOST."
fi 