#!/bin/bash

echo "🧹 Starting cleanup..."

# 1. Empty Trash (safe mode: keep structure)
echo "🗑️ Emptying Trash..."
rm -rf ~/.local/share/Trash/files/*
rm -rf ~/.local/share/Trash/info/*

# Alternative (uncomment if you want full wipe)
# rm -rf ~/.local/share/Trash/*

# 2. Clear /tmp
echo "🧼 Clearing /tmp..."
sudo rm -rf /tmp/*

# 3. Clear /var/tmp
echo "🧼 Clearing /var/tmp..."
sudo rm -rf /var/tmp/*

echo "✅ Cleanup completed!"