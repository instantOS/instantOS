#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "usage: $0 ISO_PATH [EXPECTED_VERSION]" >&2
    exit 2
}

fail() {
    echo "ISO verification failed: $1" >&2
    exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

iso_path="$1"
expected_version="${2:-}"
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

echo "verified instantOS customizations in $(basename "$iso_path")"
