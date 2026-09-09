#!/usr/bin/env bash
# Setup script for running instantOS VM natively inside Google Colab (without Docker)
if [[ ! -d "/content" ]]; then
    echo "Error: This script is intended only for Google Colab environments." >&2
    echo "On local machines or Codespaces, use 'just build-iso' or 'just vm-up'." >&2
    exit 1
fi

echo "==> Setting up native QEMU & noVNC in Google Colab..."

# 1. Install QEMU, noVNC, websockify, and build tools directly via apt
sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-x86 qemu-utils novnc websockify genisoimage

# 2. Install 'just' task runner if missing
if ! command -v just >/dev/null 2>&1; then
    echo "--> Installing 'just'..."
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin
fi

# 3. Create noVNC index redirect so port 8006 opens vnc.html automatically
if [[ -d /usr/share/novnc && ! -f /usr/share/novnc/index.html ]]; then
    sudo ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html
fi

echo "==> Colab dependencies installed successfully!"
