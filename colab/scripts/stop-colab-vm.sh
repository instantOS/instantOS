#!/usr/bin/env bash
# Stop native QEMU VM and noVNC web server
if [[ ! -d "/content" ]]; then
    echo "Error: This script is intended only for Google Colab environments." >&2
    exit 1
fi

echo "Stopping instantOS VM and noVNC web server..."
pkill -f "websockify.*8006" 2>/dev/null || true
pkill -f "qemu-system-x86_64.*instantos-vm" 2>/dev/null || true
echo "✅ VM stopped."
