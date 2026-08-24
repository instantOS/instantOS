# instantOS justfile
# Run `just` or `just --list` to view available tasks.

set shell := ["bash", "-eo", "pipefail", "-c"]

# Default recipe: list available recipes
default:
    @just --list

# Build the live ISO (auto-detects: native on Arch, Docker elsewhere)
build-iso *FLAGS="":
    #!/usr/bin/env bash
    set -eo pipefail
    if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null 2>&1; then
      echo "Arch Linux environment detected. Building ISO natively..."
      just build-iso-native {{FLAGS}}
    else
      echo "Non-Arch environment detected. Building ISO in Arch Linux Docker container..."
      just build-iso-docker {{FLAGS}}
    fi

# Build the live ISO inside an Arch Linux Docker container
build-iso-docker *FLAGS="":
    docker run --privileged --rm \
      -v "{{justfile_directory()}}:/workspace" \
      -w /workspace \
      -e SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}" \
      archlinux:base-devel \
      bash -c "set -e; pacman -Syu --noconfirm --needed archiso git sudo curl; ./iso/build.sh {{FLAGS}}"
    sudo chown -R $USER:$USER "{{justfile_directory()}}/iso/build"

# Build the live ISO natively (requires an Arch Linux host with pacman)
build-iso-native *FLAGS="":
    "{{justfile_directory()}}/iso/build.sh" {{FLAGS}}

# Download the latest prebuilt instantOS release ISO from GitHub
download-iso:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Fetching latest instantOS release ISO metadata..."
    url=$(curl -s https://api.github.com/repos/instantOS/instantOS/releases/latest | \
      grep "browser_download_url.*\.iso\"" | cut -d : -f 2,3 | tr -d '\" ' | head -n 1)
    if [[ -z "$url" ]]; then
      echo "Error: Could not find release ISO URL" >&2
      exit 1
    fi
    echo "Downloading from $url..."
    curl -L -o "{{justfile_directory()}}/instantos.iso" "$url"
    echo "Downloaded to instantos.iso ($(du -h "{{justfile_directory()}}/instantos.iso" | cut -f1))"

# Generate SHA256 checksums for all ISO files in iso/build/iso
checksums:
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{justfile_directory()}}/iso/build/iso"
    shopt -s nullglob
    iso_files=(./*.iso)
    if (( ${#iso_files[@]} == 0 )); then
      echo "No ISO files found in iso/build/iso" >&2
      exit 1
    fi
    for iso_file in "${iso_files[@]}"; do
      sha256sum "$iso_file" > "${iso_file}.sha256"
    done
    ls -lh

# Start the QEMU test VM (auto-detects KVM acceleration vs software TCG mode)
vm-up:
    #!/usr/bin/env bash
    set -eo pipefail
    if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
      echo "KVM acceleration detected (/dev/kvm). Starting high-performance VM..."
      just vm-up-kvm
    else
      echo "No KVM device found. Starting software-emulated VM (720p TCG mode)..."
      just vm-up-tcg
    fi

# Start the high-performance KVM-accelerated test VM
vm-up-kvm:
    docker compose -f "{{justfile_directory()}}/docker-compose.yml" up -d

# Start the software-emulated (no-KVM) test VM
vm-up-tcg:
    docker compose -f "{{justfile_directory()}}/docker-compose.tcg.yml" up -d

# Stop any running test VM
vm-down:
    @docker compose -f "{{justfile_directory()}}/docker-compose.yml" down 2>/dev/null || true
    @docker compose -f "{{justfile_directory()}}/docker-compose.tcg.yml" down 2>/dev/null || true

# Follow logs from the running test VM
vm-logs:
    @docker compose -f "{{justfile_directory()}}/docker-compose.yml" logs -f 2>/dev/null || \
     docker compose -f "{{justfile_directory()}}/docker-compose.tcg.yml" logs -f

# Check tracked shell scripts with shellcheck and shfmt
lint:
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{justfile_directory()}}"
    while IFS= read -r -d '' file; do
      if [[ "$file" == iso/releng/* ]]; then
        continue
      fi
      if [[ -f "$file" ]] && head -n 1 "$file" | grep -Eq '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)'; then
        printf '%s\0' "$file"
      fi
    done < <(git ls-files -z) > /tmp/instantos-shell-files
    
    count="$(tr -cd '\0' < /tmp/instantos-shell-files | wc -c)"
    echo "Found ${count} tracked shell scripts"
    if (( count > 0 )); then
      xargs -0 --no-run-if-empty shellcheck --severity=warning -- < /tmp/instantos-shell-files
      xargs -0 --no-run-if-empty shfmt -d -i 4 -ci -- < /tmp/instantos-shell-files
      echo "All shell checks passed!"
    fi
    rm -f /tmp/instantos-shell-files

    # Check Jupyter notebooks (JSON syntax + official nbformat schema + Ruff linter)
    mapfile -t notebooks < <(git ls-files "*.ipynb")
    if (( ${#notebooks[@]} > 0 )); then
      if command -v uvx >/dev/null 2>&1; then
        uvx --from nbformat python -c "import sys, nbformat; [nbformat.validate(nbformat.read(p, as_version=4)) for p in sys.argv[1:]]; print('Official Jupyter nbformat schema: PASSED')" "${notebooks[@]}"
        uvx ruff check "${notebooks[@]}"
      else
        for nb in "${notebooks[@]}"; do
          python3 -m json.tool "$nb" > /dev/null
        done
        if command -v ruff >/dev/null 2>&1; then
          ruff check "${notebooks[@]}"
        fi
      fi
      echo "All notebook checks passed!"
    fi

# Format tracked shell scripts with shfmt
fmt:
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{justfile_directory()}}"
    while IFS= read -r -d '' file; do
      if [[ "$file" == iso/releng/* ]]; then
        continue
      fi
      if [[ -f "$file" ]] && head -n 1 "$file" | grep -Eq '^#!.*(/|env[[:space:]]+)(ba|da|k|z)?sh([[:space:]]|$)'; then
        printf '%s\0' "$file"
      fi
    done < <(git ls-files -z) | xargs -0 --no-run-if-empty shfmt -w -i 4 -ci --
    echo "Formatted shell scripts."

# Remove ISO build directory and temporary build artifacts
clean:
    sudo rm -rf iso/build/
