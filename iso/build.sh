#!/bin/bash

# produce an installation iso for instantOS
# run this on an instantOS installation
# Depending on your setup might also work on Arch or Manjaro

echo "starting build of instantOS live iso"
set -eo pipefail

instantinstall archiso

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
[ "$ISO_BUILD" ] || ISO_BUILD="$SCRIPT_DIR/build"
echo "iso will be built in $ISO_BUILD"

[ -e "$ISO_BUILD" ] && echo "removing existing iso" && sudo rm -rf "$ISO_BUILD"/
mkdir -p "$ISO_BUILD"
cd "$ISO_BUILD"

sleep 1

cp -r "$SCRIPT_DIR/releng" "$ISO_BUILD/instantlive"
cp "$SCRIPT_DIR"/syslinux/* "$ISO_BUILD/instantlive/syslinux/"

ensurerepo() {
    local url="$1"
    local reponame="${url%.git}"
    reponame="${reponame##*/}"
    mkdir -p "$ISO_BUILD/workspace"
    if [[ ! -d "$ISO_BUILD/workspace/$reponame" ]]; then
        git clone --depth 1 "$url" "$ISO_BUILD/workspace/$reponame"
    else
        git -C "$ISO_BUILD/workspace/$reponame" pull --ff-only
    fi
}

add_liveutils_assets() {
    ensurerepo https://github.com/instantOS/liveutils
    local src="$ISO_BUILD/workspace/liveutils"
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

add_liveutils_assets

cd "$ISO_BUILD/"
mkdir "$ISO_BUILD"/iso
sudo mkarchiso -v "$ISO_BUILD/instantlive" -o "$ISO_BUILD/iso/"

echo "finished building instantOS installation iso"
