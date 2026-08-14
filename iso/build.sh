#!/bin/bash

# produce an installation iso for instantOS
# run this on an instantOS installation
# Depending on your setup might also work on Arch or Manjaro

echo "starting build of instantOS live iso"
set -eo pipefail

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "installing archiso build tools"
    sudo pacman -S --needed archiso
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)
[ "$ISO_BUILD" ] || ISO_BUILD="$SCRIPT_DIR/build"
echo "iso will be built in $ISO_BUILD"

DOTFILES_URL="https://github.com/instantOS/dotfiles"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
DOTFILES_REF="${DOTFILES_REF:-$DOTFILES_BRANCH}"
INSTANTTOOLS_URL="https://github.com/instantOS/instantTOOLS"
INSTANTTOOLS_BRANCH="${INSTANTTOOLS_BRANCH:-main}"
INSTANTTOOLS_REF="${INSTANTTOOLS_REF:-$INSTANTTOOLS_BRANCH}"
LIVEUTILS_URL="https://github.com/instantOS/liveutils"
LIVEUTILS_BRANCH="${LIVEUTILS_BRANCH:-main}"
LIVEUTILS_REF="${LIVEUTILS_REF:-$LIVEUTILS_BRANCH}"

[ -e "$ISO_BUILD" ] && echo "removing existing iso" && sudo rm -rf "$ISO_BUILD"/
mkdir -p "$ISO_BUILD"
cd "$ISO_BUILD"

sleep 1

cp -r "$SCRIPT_DIR/releng" "$ISO_BUILD/instantlive"
# `overlay/` is the single source of truth for instantOS airootfs additions.
cp -a "$SCRIPT_DIR/overlay/." "$ISO_BUILD/instantlive/airootfs/"
cp "$SCRIPT_DIR"/syslinux/* "$ISO_BUILD/instantlive/syslinux/"

install -Dm755 "$REPO_ROOT/rootinstall.sh" \
    "$ISO_BUILD/instantlive/airootfs/usr/share/instantos/rootinstall.sh"

# Record ISO build date as the live image version
mkdir -p "$ISO_BUILD/instantlive/airootfs/etc/instantos"
ISO_VERSION="$(date -u --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
echo "$ISO_VERSION" >"$ISO_BUILD/instantlive/airootfs/etc/instantos/version"

fetch_source_repo() {
    local url="$1"
    local name="$2"
    local ref="$3"
    local branch="$4"
    local dest="$ISO_BUILD/sources/$name"

    echo "fetching $name from $url at $ref"
    mkdir -p "$ISO_BUILD/sources"
    git init -q "$dest"
    git -C "$dest" remote add origin "$url"
    git -C "$dest" fetch --depth 1 origin "$ref"
    git -C "$dest" -c advice.detachedHead=false \
        checkout -q -B "$branch" FETCH_HEAD
}

source_commit() {
    local name="$1"
    local commit
    commit="$(git -C "$ISO_BUILD/sources/$name" rev-parse HEAD)"
    if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
        echo "invalid commit for $name: $commit" >&2
        return 1
    fi
    printf '%s\n' "$commit"
}

prepare_build_inputs() {
    local inputs="$ISO_BUILD/instantlive/airootfs/usr/share/instantos/build-inputs"
    local manifest="$ISO_BUILD/instantlive/airootfs/usr/share/instantos/build-sources.env"

    fetch_source_repo "$DOTFILES_URL" dotfiles "$DOTFILES_REF" "$DOTFILES_BRANCH"
    fetch_source_repo "$INSTANTTOOLS_URL" instantTOOLS \
        "$INSTANTTOOLS_REF" "$INSTANTTOOLS_BRANCH"
    fetch_source_repo "$LIVEUTILS_URL" liveutils "$LIVEUTILS_REF" "$LIVEUTILS_BRANCH"

    mkdir -p "$inputs"
    cp -a "$ISO_BUILD/sources/dotfiles" "$inputs/dotfiles"
    cp -a "$ISO_BUILD/sources/instantTOOLS" "$inputs/instantTOOLS"

    {
        printf 'DOTFILES_URL=%q\n' "$DOTFILES_URL"
        printf 'DOTFILES_BRANCH=%q\n' "$DOTFILES_BRANCH"
        printf 'DOTFILES_COMMIT=%q\n' "$(source_commit dotfiles)"
        printf 'INSTANTTOOLS_URL=%q\n' "$INSTANTTOOLS_URL"
        printf 'INSTANTTOOLS_BRANCH=%q\n' "$INSTANTTOOLS_BRANCH"
        printf 'INSTANTTOOLS_COMMIT=%q\n' "$(source_commit instantTOOLS)"
        printf 'LIVEUTILS_URL=%q\n' "$LIVEUTILS_URL"
        printf 'LIVEUTILS_BRANCH=%q\n' "$LIVEUTILS_BRANCH"
        printf 'LIVEUTILS_COMMIT=%q\n' "$(source_commit liveutils)"
    } >"$manifest"
}

add_liveutils_assets() {
    local src="$ISO_BUILD/sources/liveutils"
    local dest="$ISO_BUILD/instantlive/airootfs/usr/share/liveutils"
    mkdir -p "$dest"
    rm -f "$dest"/*
    if [[ -f "$src/wallpaper.png" ]]; then
        cp "$src"/wallpaper.png "$dest"/
    fi
    if compgen -G "$src/assets/*.jpg" >/dev/null; then
        cp "$src"/assets/*.jpg "$dest"/
    fi
}

prepare_build_inputs
add_liveutils_assets

cd "$ISO_BUILD/"
mkdir "$ISO_BUILD"/iso
sudo mkarchiso -v -o "$ISO_BUILD/iso/" "$ISO_BUILD/instantlive"

shopt -s nullglob
iso_files=("$ISO_BUILD"/iso/*.iso)
if ((${#iso_files[@]} != 1)); then
    echo "expected exactly one ISO, found ${#iso_files[@]}" >&2
    exit 1
fi

"$SCRIPT_DIR/verify.sh" "${iso_files[0]}" "$ISO_VERSION"

echo "finished building instantOS installation iso"
