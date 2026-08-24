#!/usr/bin/env bash
# Stop native QEMU VM and noVNC web server
set -eo pipefail

echo "Stopping instantOS VM and noVNC web server..."
pkill -f "websockify.*8006" 2>/dev/null || true
pkill -f "qemu-system-x86_64.*instantos-vm" 2>/dev/null || true
echo "✅ VM stopped."
