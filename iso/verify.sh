#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "usage: $0 ISO_PATH [EXPECTED_VERSION] [--offline]" >&2
    exit 2
}

fail() {
    echo "ISO verification failed: $1" >&2
    exit 1
}

offline=0
positional=()
for arg in "$@"; do
    case "$arg" in
        --offline) offline=1 ;;
        *) positional+=("$arg") ;;
    esac
done
((${#positional[@]} >= 1 && ${#positional[@]} <= 2)) || usage

iso_path="${positional[0]}"
expected_version="${positional[1]:-}"
[[ -f "$iso_path" ]] || fail "ISO does not exist: $iso_path"

for command in bsdtar git unsquashfs; do
    command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf -- "$tmpdir"
}
trap cleanup EXIT

mapfile -t rootfs_images < <(bsdtar -tf "$iso_path" | grep -E '/airootfs\.sfs$')
if ((${#rootfs_images[@]} != 1)); then
    fail "expected exactly one squashfs root image, found ${#rootfs_images[@]}"
fi

rootfs="$tmpdir/airootfs.sfs"
bsdtar -xOf "$iso_path" "${rootfs_images[0]}" >"$rootfs"
[[ -s "$rootfs" ]] || fail "the squashfs root image is empty"

image_cat() {
    unsquashfs -cat "$rootfs" "$1" 2>/dev/null
}

assert_file() {
    image_cat "$1" >/dev/null || fail "missing expected file: /$1"
}

assert_contains() {
    local path="$1"
    local expected="$2"
    image_cat "$path" | grep -Fq -- "$expected" ||
        fail "/$path does not contain: $expected"
}

if ! marker="$(image_cat opt/instantos/.setup-done)"; then
    failure_details="$(image_cat opt/instantos/.setup-failed || true)"
    if [[ -n "$failure_details" ]]; then
        fail "instantOS setup completion marker is missing ($failure_details)"
    fi
    fail "instantOS setup completion marker is missing"
fi
grep -Fxq 'status=complete' <<<"$marker" || fail "instantOS setup did not complete"

source_manifest="$(image_cat usr/share/instantos/build-sources.env)" ||
    fail "build source manifest is missing"

for source in dotfiles instanttools liveutils; do
    marker_key="${source}_commit"
    marker_commit="$(sed -n "s/^${marker_key}=//p" <<<"$marker")"
    [[ "$marker_commit" =~ ^[0-9a-f]{40}$ ]] ||
        fail "invalid $marker_key in setup marker"

    manifest_key="${source^^}_COMMIT"
    manifest_commit="$(sed -n "s/^${manifest_key}=//p" <<<"$source_manifest")"
    [[ "$manifest_commit" == "$marker_commit" ]] ||
        fail "$source commit differs between the manifest and setup marker"
done

assert_file opt/instantos/rootinstall
assert_file home/instantos/.zshrc
assert_file home/instantos/.config/instant/dots.toml
assert_file home/instantos/.local/share/instant/dots/dotfiles/.git/config
assert_file usr/local/bin/ibuild
assert_file usr/local/share/instanttools/version
assert_contains etc/greetd/config.toml 'user = "instantos"'
assert_contains etc/greetd/config.toml 'instantwm --backend drm'
assert_contains home/instantos/.config/instant/dots.toml \
    'https://github.com/instantOS/dotfiles'
assert_contains home/instantos/.local/share/instant/dots/dotfiles/.git/config \
    'https://github.com/instantOS/dotfiles'

dotfiles_branch="$(sed -n 's/^DOTFILES_BRANCH=//p' <<<"$source_manifest")"
git check-ref-format --branch "$dotfiles_branch" >/dev/null 2>&1 ||
    fail "invalid dotfiles branch in build source manifest"
assert_contains home/instantos/.local/share/instant/dots/dotfiles/.git/HEAD \
    "ref: refs/heads/$dotfiles_branch"
installed_dotfiles_commit="$(
    image_cat "home/instantos/.local/share/instant/dots/dotfiles/.git/refs/heads/$dotfiles_branch"
)"
dotfiles_commit="$(sed -n 's/^dotfiles_commit=//p' <<<"$marker")"
[[ "$installed_dotfiles_commit" == "$dotfiles_commit" ]] ||
    fail "installed dotfiles revision does not match the setup marker"

installed_zshrc_hash="$(image_cat home/instantos/.zshrc | sha256sum | cut -d ' ' -f 1)"
source_zshrc_hash="$(
    image_cat home/instantos/.local/share/instant/dots/dotfiles/dots/.zshrc |
        sha256sum | cut -d ' ' -f 1
)"
[[ "$installed_zshrc_hash" == "$source_zshrc_hash" ]] ||
    fail "the live user's .zshrc does not match the dotfiles source"

instanttools_commit="$(sed -n 's/^instanttools_commit=//p' <<<"$marker")"
installed_instanttools_version="$(image_cat usr/local/share/instanttools/version)"
[[ "$installed_instanttools_version" == "${instanttools_commit:0:10}" ]] ||
    fail "installed instantTOOLS version does not match the setup marker"

if [[ -n "$expected_version" ]]; then
    installed_version="$(image_cat etc/instantos/version)"
    [[ "$installed_version" == "$expected_version" ]] ||
        fail "version mismatch: expected $expected_version, found $installed_version"
fi

if image_cat etc/pacman.d/hooks/90-instantos-setup.hook >/dev/null 2>&1; then
    fail "build-only instantOS setup hook remains in the final image"
fi

# ---------------------------------------------------------------------------
# Offline bundle checks (offline variant only)
# ---------------------------------------------------------------------------
if ((offline)); then
    bundle_listing="$tmpdir/bundle-listing.txt"
    bsdtar -tf "$iso_path" >"$bundle_listing"

    for repo in core extra multilib instant; do
        grep -Fxq "offline-repo/$repo/os/x86_64/$repo.db" "$bundle_listing" ||
            fail "bundle repository database missing: offline-repo/$repo"
    done

    grep -Fxq "offline-repo/regions/regions.html" "$bundle_listing" ||
        fail "bundle mirror-region snapshot is missing regions.html"
    grep -qE '^offline-repo/regions/mirrorlists/[^/]+\.txt$' "$bundle_listing" ||
        fail "bundle mirror-region snapshot has no per-country mirrorlists"

    # every manifest package must be staged, whatever its version
    bsdtar -xOf "$iso_path" offline-repo/packages.list >"$tmpdir/manifest.txt" ||
        fail "bundle manifest packages.list is missing"
    grep -E '^offline-repo/(core|extra|multilib|instant)/os/x86_64/[^/]+\.pkg\.tar\.zst$' \
        "$bundle_listing" |
        awk '{p=$0; sub(/^.*x86_64\//, "", p); sub(/-[^-]+-[^-]+-[^-]+\.pkg\.tar\.zst$/, "", p); print p}' |
        sort -u >"$tmpdir/staged-names.txt"
    grep -Ev '^\s*$|^#' "$tmpdir/manifest.txt" | sort -u >"$tmpdir/manifest-names.txt"
    missing_packages=$(comm -23 "$tmpdir/manifest-names.txt" "$tmpdir/staged-names.txt")
    [[ -z "$missing_packages" ]] ||
        fail "packages in the manifest but not in the bundle: $missing_packages"

    # signed repositories must ship every signature; the instant repo is
    # unsigned (SigLevel = Optional TrustAll travels with the section)
    while IFS= read -r archive; do
        grep -Fxq "$archive.sig" "$bundle_listing" ||
            fail "package archive without a signature: $archive"
    done < <(grep -E '^offline-repo/(core|extra|multilib)/os/x86_64/[^/]+\.pkg\.tar\.zst$' \
        "$bundle_listing")

    # ISO9660 has a 4 GiB single-file limit; keep every file well under it
    bsdtar -tvf "$iso_path" >"$tmpdir/bundle-sizes.txt"
    [[ -s "$tmpdir/bundle-sizes.txt" ]] || fail "ISO content listing is empty"
    bad_format=$(awk '$5 !~ /^[0-9]+$/ { print $0; exit }' "$tmpdir/bundle-sizes.txt")
    [[ -z "$bad_format" ]] ||
        fail "could not assert file sizes; unexpected bsdtar -tvf output: $bad_format"
    oversized=$(awk '$5 + 0 > 4227858432 { print $0; exit }' "$tmpdir/bundle-sizes.txt")
    [[ -z "$oversized" ]] ||
        fail "file crosses the 4 GiB single-file safety margin: $oversized"

    # the live image must carry and prefer the bundle
    assert_file usr/share/instantos/build-inputs/dotfiles/.git/config
    assert_contains etc/pacman.conf 'Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch'
    assert_contains etc/pacman.conf 'SigLevel    = Optional TrustAll'
    assert_contains etc/pacman.d/mirrorlist \
        'Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch'
    first_server="$(image_cat etc/pacman.d/mirrorlist | grep -E '^[[:space:]]*Server' | head -n 1)"
    grep -Fq 'file://' <<<"$first_server" ||
        fail "the shipped mirrorlist does not prefer the offline bundle: $first_server"

    echo "verified offline bundle in $(basename "$iso_path")"
fi

echo "verified instantOS customizations in $(basename "$iso_path")"
