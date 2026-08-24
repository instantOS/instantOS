#!/usr/bin/env bash
# Build instantOS ISO inside a headless Arch Linux QEMU Virtual Machine.
# This works in Google Colab or any environment without Docker / loop device permissions.
set -eo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)
BUILD_DIR="$REPO_ROOT/vm-data/arch-builder"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

ARCH_IMAGE_URL="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-genericcloud.qcow2"
BASE_IMAGE="arch-cloud-base.qcow2"
BUILD_DISK="arch-build-disk.qcow2"
CIDATA_ISO="cidata.iso"

# 1. Download Arch Linux generic cloud image if not cached
if [[ ! -f "$BASE_IMAGE" ]]; then
    echo "==> Downloading official Arch Linux cloud image (~600MB)..."
    curl -L -o "$BASE_IMAGE" "$ARCH_IMAGE_URL"
fi

# 2. Create a fast copy-on-write snapshot disk for this build
echo "==> Preparing build disk snapshot..."
rm -f "$BUILD_DISK"
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$BUILD_DISK" 25G >/dev/null

# 3. Create Cloud-Init configuration
cat <<'EOF' > meta-data
instance-id: arch-iso-builder
local-hostname: arch-builder
EOF

cat <<'EOF' > user-data
#cloud-config
write_files:
  - path: /root/build.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      set -eo pipefail
      echo "----------------------------------------------------"
      echo "==> Starting instantOS ISO build inside Arch VM..."
      echo "----------------------------------------------------"
      mkdir -p /workspace
      mount -t 9p -o trans=virtio,version=9p2000.L workspace /workspace
      
      echo "==> Updating pacman and installing archiso..."
      pacman -Sy --noconfirm --needed archiso git sudo curl
      
      echo "==> Building ISO in fast local VM storage (/tmp/iso-build)..."
      export ISO_BUILD="/tmp/iso-build"
      mkdir -p "$ISO_BUILD"
      /workspace/iso/build.sh
      
      echo "==> Copying built ISO to host workspace..."
      mkdir -p /workspace/iso/build/iso
      cp -f "$ISO_BUILD"/iso/*.iso /workspace/iso/build/iso/
      cp -f "$ISO_BUILD"/iso/*.iso /workspace/instantos.iso
      echo "==> Finished! Output saved to instantos.iso"
      poweroff

runcmd:
  - /root/build.sh
EOF

# 4. Generate Cloud-Init NoCloud configuration ISO
if command -v genisoimage >/dev/null 2>&1; then
    genisoimage -output "$CIDATA_ISO" -volid cidata -joliet -rock user-data meta-data >/dev/null 2>&1
elif command -v xorrisofs >/dev/null 2>&1; then
    xorrisofs -output "$CIDATA_ISO" -volid cidata -joliet -rock user-data meta-data >/dev/null 2>&1
else
    echo "Error: genisoimage or xorrisofs is required. Run 'sudo apt-get install -y genisoimage'" >&2
    exit 1
fi

# 5. Check hardware acceleration
KVM_FLAGS=()
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    echo "⚡ KVM acceleration enabled!"
    KVM_FLAGS=("-enable-kvm" "-cpu" "host")
else
    echo "⚙️ Running with QEMU software emulation (TCG)..."
    KVM_FLAGS=("-cpu" "max")
fi

echo "==> Booting headless Arch Linux VM to build instantOS..."
echo "==> Live VM output:"
echo "----------------------------------------------------"

qemu-system-x86_64 \
    "${KVM_FLAGS[@]}" \
    -m 4G \
    -smp 4 \
    -nographic \
    -drive file="$BUILD_DISK",if=virtio \
    -drive file="$CIDATA_ISO",format=raw,if=virtio \
    -virtfs local,path="$REPO_ROOT",mount_tag=workspace,security_model=none,id=workspace \
    -net nic,model=virtio -net user

echo "----------------------------------------------------"
if [[ -f "$REPO_ROOT/instantos.iso" ]]; then
    echo "✅ Success! instantOS ISO built successfully at $REPO_ROOT/instantos.iso"
else
    echo "❌ Error: Build finished but instantos.iso was not found." >&2
    exit 1
fi
