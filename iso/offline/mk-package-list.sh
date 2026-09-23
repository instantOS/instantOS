#!/usr/bin/env bash
# Generate the offline bundle package list (full enum-union scope).
#
# The offline ISO must be able to install every path the install wizard can
# produce: every kernel, desktop environment, display manager, boolean
# option and locale, for every hardware shape the plan branches on. The
# oracle is `ins arch exec --dry-run`: one questions file per plan variant
# is dry-run and every package that would be installed (pacstrap +
# `pacman -S` lines) is unioned into packages.list.
#
# Extra entries the oracle cannot see are appended explicitly:
#   gum, ntfs-3g — the installer installs these on the live system at ask
#   time (ask.rs install_live_iso_dependencies), which no exec-path
#   dry-run covers.
#
# Usage: mk-package-list.sh [-o OUTPUT] [--force]
#   -o OUTPUT   where to write the list (default: packages.list next to
#               this script; "-" for stdout)
#   --force     fail instead of falling back to the committed list when
#               no usable `ins` binary is available
#
# The `ins` binary is taken from $INS_BIN, then $PATH, then built from
# $INSTANTCLI_DIR (default: the instantCLI checkout next to this repo).
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
repo_root=$(cd -- "$script_dir/../.." &>/dev/null && pwd)

output="$script_dir/packages.list"
force=0
while (($#)); do
    case "$1" in
        -o)
            output="$2"
            shift 2
            ;;
        --force)
            force=1
            shift
            ;;
        *)
            echo "usage: $0 [-o OUTPUT] [--force]" >&2
            exit 2
            ;;
    esac
done

committed_list="$script_dir/packages.list"

fallback_to_committed() {
    if ((force)); then
        echo "error: no usable ins binary and --force forbids the committed fallback" >&2
        exit 1
    fi
    if [[ ! -s "$committed_list" ]]; then
        echo "error: no usable ins binary and no committed packages.list to fall back to" >&2
        exit 1
    fi
    echo "warning: falling back to the committed packages.list" >&2
    echo "warning: regenerate after instantCLI changes: iso/offline/mk-package-list.sh" >&2
    if [[ "$output" == "-" ]]; then
        cat "$committed_list"
    elif [[ "$output" != "$committed_list" ]]; then
        cp "$committed_list" "$output"
    fi
}

find_ins() {
    if [[ -n "${INS_BIN:-}" ]]; then
        echo "$INS_BIN"
        return
    fi
    if command -v ins >/dev/null 2>&1; then
        command -v ins
        return
    fi
    local cli_dir="${INSTANTCLI_DIR:-$repo_root/../instantCLI}"
    if command -v cargo >/dev/null 2>&1 && [[ -f "$cli_dir/Cargo.toml" ]]; then
        echo "no ins on PATH; building it from $cli_dir (cargo)" >&2
        (cd "$cli_dir" && cargo build --release --bin ins)
        local built="$cli_dir/target/release/ins"
        if [[ -x "$built" ]]; then
            echo "$built"
            return
        fi
    fi
    return 1
}

if ! ins_bin=$(find_ins); then
    echo "no ins binary found (set INS_BIN, install ins, or provide cargo + INSTANTCLI_DIR)" >&2
    fallback_to_committed
    exit 0
fi

workdir=$(mktemp -d)
cleanup() {
    rm -rf -- "$workdir"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Variant matrix
#
# Sweeps cover every conditional package source in the execution layer:
#   kernel x GPU        driver packages, nvidia flavour per kernel, DKMS headers
#   DE x DM x xorg      display stack, incl. the lightdm default xorg-on
#   plymouth x minimal  config packages + mkinitcpio hooks
#   filesystem/encrypt  btrfs-progs, lvm2, cryptsetup
#   locale              language-specific packages
#   boot/CPU/BT/NIC/VM  firmware splits, microcode, efibootmgr, blueman, guests
# ---------------------------------------------------------------------------

# Invariant answers and system_info. Sweepable keys are replaced per
# variant with set_answer/set_info — TOML forbids duplicate keys, so an
# override must replace, never append.
base_answers='
Hostname = "bundle-union"
Username = "tester"
Password = "correct-horse-battery-staple"
Keymap = "us"
Disk = "/dev/bundle"
PartitioningMethod = "automatic"
MirrorRegion = "Germany"
Timezone = "Europe/Berlin"
Locale = "en_US.UTF-8"
Kernel = "linux"
DesktopEnvironment = "instantwm"
DisplayManager = "gdm"
RootFilesystem = "btrfs"
BtrfsCompression = "zstd"
UseEncryption = "no"
UsePlymouth = "yes"
UseXorg = "no"
MinimalMode = "no"
LogUpload = "no"
'

base_system_info='
boot_mode = "BIOS"
has_amd_cpu = false
has_intel_cpu = true
gpus = ["Intel"]
vm_type = "kvm"
internet_connected = true
architecture = "x86_64"
distro = "arch"
total_ram_gb = 8
network_vendor_ids = ["8086"]
has_bluetooth = true
'

set_answer() {
    # set_answer <config> <Key> <toml-value> — replace the key's line, or
    # append the key when the base does not carry it (e.g. the encryption
    # password, which only exists in encrypted variants)
    local config="$1" key="$2" value="$3"
    if printf '%s\n' "$config" | grep -qE "^${key} = "; then
        printf '%s\n' "$config" | sed -E "s|^(${key}) = .*|\1 = ${value}|"
    else
        printf '%s\n%s = %s\n' "$config" "$key" "$value"
    fi
}

set_info() {
    # set_info <system-info> <key> <toml-value> — same replace-or-append
    local config="$1" key="$2" value="$3"
    if printf '%s\n' "$config" | grep -qE "^${key} = "; then
        printf '%s\n' "$config" | sed -E "s|^(${key}) = .*|\1 = ${value}|"
    else
        printf '%s\n%s = %s\n' "$config" "$key" "$value"
    fi
}

emit_variant() {
    # emit_variant <file> <answers> <system-info>
    local file="$1" answers="$2" system="$3"
    {
        echo "# auto-generated by iso/offline/mk-package-list.sh"
        echo "completed_steps = []"
        echo "step_dependency_fingerprints = {}"
        echo ""
        echo "[answers]"
        printf '%s\n' "$answers"
        echo ""
        echo "[system_info]"
        printf '%s\n' "$system"
    } >"$file"
}

# Extract packages from dry-run output: `pacstrap /mnt p...` and
# `pacman -S --noconfirm --needed p...` lines. Flags are skipped; every
# other pacman mode (-Sy, -Scc, -R, ...) is ignored.
collect_packages() {
    awk '
        /^\[DRY RUN\] / {
            line = substr($0, 11)          # strip the "[DRY RUN] " prefix
            n = split(line, tok, /[ \t]+/)
            program = tok[1]
            i = 2
            if (program == "pacstrap") {
                while (i <= n && tok[i] ~ /^-/) i++
                if (i > n) next
                i++                        # mount point
            } else if (program == "pacman") {
                if (i > n || tok[i] != "-S") next
                i++
            } else {
                next
            }
            for (; i <= n; i++) {
                if (tok[i] != "" && tok[i] !~ /^-/) print tok[i]
            }
        }
    '
}

# --- variant definitions ----------------------------------------------------
variants_dir="$workdir/variants"
mkdir -p "$variants_dir"

add_variant() {
    # add_variant <label> <answers> <system-info>; duplicate final configs
    # are detected by hash and dry-run only once.
    local label="$1" answers="$2" system="$3"
    local file
    file="$variants_dir/$(printf '%s' "$answers$system" | sha256sum | cut -d' ' -f1).toml"
    if [[ -e "$file" ]]; then
        return
    fi
    emit_variant "$file" "$answers" "$system"
    printf '%s\t%s\n' "${file##*/}" "$label" >>"$variants_dir/index"
}

add() {
    # add <label> <Key=value ...> <key=value ...> — answers first, then a
    # `--` separator, then system_info overrides. A `~Key` token deletes an
    # answer instead of replacing it, for keys whose question would not be
    # asked in this configuration (validate_imported_context rejects
    # stored-but-irrelevant answers).
    local label="$1"
    shift
    local answers="$base_answers" system="$base_system_info" in_system=0
    local pair key value
    for pair in "$@"; do
        if [[ "$pair" == "--" ]]; then
            in_system=1
            continue
        fi
        if [[ "$pair" == "~"* ]]; then
            # NB: the tilde must be escaped here — an unquoted one in the
            # pattern undergoes tilde expansion and never matches.
            key="${pair#\~}"
            answers=$(printf '%s\n' "$answers" | sed -E "/^${key} = /d")
            continue
        fi
        key="${pair%%=*}"
        value="${pair#*=}"
        if ((in_system)); then
            system=$(set_info "$system" "$key" "$value")
        else
            answers=$(set_answer "$answers" "$key" "\"$value\"")
        fi
    done
    add_variant "$label" "$answers" "$system"
}

# kernel x GPU: driver packages, nvidia kernel flavour, DKMS headers.
# GPU "none" also clears the NIC list so the full linux-firmware meta
# fallback path is covered.
for kernel in linux linux-lts linux-zen; do
    add "k-$kernel-nvidia" "Kernel=$kernel" -- "gpus=[\"Nvidia\"]"
    add "k-$kernel-amd" "Kernel=$kernel" -- "gpus=[\"Amd\"]"
    add "k-$kernel-intel" "Kernel=$kernel" -- 'gpus=["Intel"]'
    add "k-$kernel-other" "Kernel=$kernel" -- 'gpus=[{ Other = "QEMU Virtual Video" }]'
    add "k-$kernel-none" "Kernel=$kernel" -- 'gpus=[]' 'network_vendor_ids=[]'
done

# desktop x display manager x xorg (union semantics make over-covering
# mutually exclusive answers free, while missing one would be a real
# offline-install hole). tty installs never ask the display-manager or
# xorg questions, so those answers must be absent there.
add "de-none/tty" "~DisplayManager" "~UseXorg" "DesktopEnvironment=none/tty"
for d in sway niri instantwm hyprland; do
    for m in gdm lightdm none; do
        for x in no yes; do
            add "de-$d-dm-$m-xorg-$x" \
                "DesktopEnvironment=$d" "DisplayManager=$m" "UseXorg=$x"
        done
    done
done

# plymouth x minimal (the remaining plan booleans have no package effect:
# autologin only writes greetd config, LogUpload is post-install tooling).
add "plymouth-off" "UsePlymouth=no"
add "minimal" "MinimalMode=yes"
add "plymouth-off-minimal" "UsePlymouth=no" "MinimalMode=yes"

# filesystem x encryption (btrfs/zstd is the base; the compression choice
# only changes mount options, never packages). ext4 never asks the
# compression question, so its answer must be absent; turning encryption
# on makes the password question (and answer) mandatory.
add "ext4" "~BtrfsCompression" "RootFilesystem=ext4"
add "encrypted" "UseEncryption=yes" "EncryptionPassword=correct-horse-battery-staple"
add "ext4-encrypted" "~BtrfsCompression" "RootFilesystem=ext4" \
    "UseEncryption=yes" "EncryptionPassword=correct-horse-battery-staple"

# locales: every language with dedicated packages in
# execution/packages.rs collect_language_packages.
for locale in en_US en_GB en_ZA de_DE fr_FR es_ES es_AR es_CL es_MX \
    it_IT ru_RU ja_JP zh_CN zh_TW pt_PT pt_BR; do
    add "locale-$locale" "Locale=$locale.UTF-8"
done

# firmware/boot/hardware conditionals.
add "uefi" -- 'boot_mode="UEFI64"'
add "amd-cpu" -- 'has_amd_cpu=true'
add "no-intel-cpu" -- 'has_intel_cpu=false'
add "no-bluetooth" -- 'has_bluetooth=false'
for vid in 104c 10ec 14c3 14e4 168c; do
    add "nic-$vid" -- "network_vendor_ids=[\"$vid\"]"
done
add "no-vm-tools" -- 'vm_type="acpi"'
add "vm-vmware" -- 'vm_type="vmware"'
add "vm-oracle" -- 'vm_type="oracle"'

# --- run the oracle ----------------------------------------------------------
mapfile -t variant_index <"$variants_dir/index"
echo "running ${#variant_index[@]} dry-run variants with $ins_bin" >&2

raw="$workdir/raw.txt"
: >"$raw"
for entry in "${variant_index[@]}"; do
    file="${entry%%$'\t'*}"
    label="${entry#*$'\t'}"
    echo "  $label" >&2
    "$ins_bin" arch exec --dry-run -f "$variants_dir/$file" >>"$raw" ||
        {
            echo "error: oracle failed for variant $label" >&2
            exit 1
        }
done

{
    echo "# instantOS offline bundle package list."
    echo "# Generated by iso/offline/mk-package-list.sh (ins arch exec --dry-run"
    echo "# union over every wizard plan variant); do not edit by hand."
    {
        collect_packages <"$raw"
        # Live-system runtime deps installed by the ask phase (file header).
        printf '%s\n' gum ntfs-3g
    } | sort -u
} >"$workdir/packages.list"

count=$(grep -cve '^\s*$\|^#' "$workdir/packages.list")
echo "union contains $count explicit packages (pacman -Sw expands this to the
full dependency closure when the bundle is built)" >&2
# The manifest is the union of explicit wizard packages, so it is small;
# what must never be missing are the sentinels of every swept axis.
for sentinel in linux linux-zen nvidia-dkms sway hyprland lightdm \
    linux-firmware-nvidia blueman instantos gum ntfs-3g; do
    grep -qx "$sentinel" "$workdir/packages.list" || {
        echo "error: sentinel package $sentinel missing from the union; the oracle sweep failed" >&2
        exit 1
    }
done
if ((count < 50)); then
    echo "error: implausibly small package list ($count entries); the oracle run failed" >&2
    exit 1
fi
if [[ "$output" == "-" ]]; then
    cat "$workdir/packages.list"
else
    mkdir -p "$(dirname -- "$output")"
    mv "$workdir/packages.list" "$output"
    echo "wrote $output" >&2
fi
