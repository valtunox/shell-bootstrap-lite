#!/bin/bash
echo "=== Quick System Health Check ==="

echo "--- Uptime & Load Average ---"
uptime

echo "--- Memory Usage ---"
free -h

echo "--- Disk Space (Root) ---"
df -h /

echo "================================="