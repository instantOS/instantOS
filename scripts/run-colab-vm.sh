#!/usr/bin/env bash
# Start instantOS QEMU VM and noVNC web server natively (for Colab / bare-metal)
if [[ ! -d "/content" ]]; then
    echo "Error: This script is intended only for Google Colab environments." >&2
    echo "On local machines or Codespaces, use 'just vm-up'." >&2
    exit 1
fi

ISO_PATH="${1:-instantos.iso}"
DISK_PATH="vm-data/storage.qcow2"

if [[ ! -f "$ISO_PATH" ]]; then
    echo "Error: ISO not found at '$ISO_PATH'. Run 'just download-iso' first." >&2
    exit 1
fi

mkdir -p vm-data

# Create 20G virtual hard drive if it doesn't exist
if [[ ! -f "$DISK_PATH" ]]; then
    echo "Creating virtual hard disk image at $DISK_PATH..."
    qemu-img create -f qcow2 "$DISK_PATH" 20G >/dev/null
fi

# Kill any previous instance of websockify / qemu
pkill -f "websockify.*8006" 2>/dev/null || true
pkill -f "qemu-system-x86_64.*instantos-vm" 2>/dev/null || true
sleep 1

# Start websockify proxy on port 8006 bridging to VNC display :0 (port 5900)
echo "Starting noVNC web server on port 8006..."
websockify --web /usr/share/novnc 8006 localhost:5900 >/dev/null 2>&1 &

# Determine if KVM acceleration is available
KVM_FLAGS=()
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    echo "⚡ KVM hardware acceleration detected!"
    KVM_FLAGS=("-enable-kvm" "-cpu" "host")
else
    echo "⚙️ Running with QEMU software emulation (TCG)..."
    KVM_FLAGS=("-cpu" "max")
fi

echo "Launching QEMU virtual machine with $ISO_PATH..."
qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -m 4G \
    -smp 4 \
    -name "instantos-vm" \
    -cdrom "$ISO_PATH" \
    -drive file="$DISK_PATH",format=qcow2,if=virtio \
    -boot d \
    -device VGA,xres=1280,yres=720,xmax=1280,ymax=720 \
    -usb -device usb-tablet \
    -net nic,model=virtio -net user \
    -vnc :0 \
    -daemonize

echo "✅ instantOS VM is running with noVNC display on port 8006!"
