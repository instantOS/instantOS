#!/usr/bin/env bash
# Prepare Google Colab environment with Docker, Just, and virtualization dependencies.
set -eo pipefail

echo "==> Setting up Google Colab environment for instantOS..."

# 1. Install 'just' task runner if missing
if ! command -v just >/dev/null 2>&1; then
    echo "--> Installing 'just'..."
    curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin
fi

# 2. Install Docker and Docker Compose if missing
if ! command -v docker >/dev/null 2>&1 || ! command -v docker-compose >/dev/null 2>&1; then
    echo "--> Installing Docker and Docker Compose..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker.io docker-compose-v2
fi

# 3. Ensure Docker daemon is running
if ! sudo docker info >/dev/null 2>&1; then
    echo "--> Starting Docker service..."
    sudo service docker start || sudo systemctl start docker || true
    sleep 2
fi

# 4. Check & fix permissions for KVM and /dev/net/tun if present
if [[ -e /dev/kvm ]]; then
    echo "--> KVM hardware acceleration detected (/dev/kvm)"
    sudo chmod 666 /dev/kvm || true
else
    echo "--> Note: /dev/kvm not found; test VM will run in software TCG mode"
fi

if [[ -e /dev/net/tun ]]; then
    sudo chmod 666 /dev/net/tun || true
fi

echo "==> Colab setup complete! Environment is ready."
