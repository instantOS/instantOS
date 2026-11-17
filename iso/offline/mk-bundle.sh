#!/usr/bin/env bash
# Build the offline pacman repository bundle from packages.list.
#
# Output: <bundle-dir>/
#   core/os/x86_64/       {core.db -> core.db.tar.gz, *.pkg.tar.zst, *.sig}
#   extra/os/x86_64/      {extra.db ...}
#   multilib/os/x86_64/   {multilib.db ...}
#   instant/os/x86_64/    {instant.db ...}          (unsigned packages)
#   regions/              mirror-region snapshot (mk-region-data.sh)
#   packages.list         manifest consumed by verify.sh
#
# Every repo enabled at install time must be bundled (a missing repo fails
# the whole `pacman -Sy`), so multilib is enabled in the scratch config even
# though the live profile ships it disabled — the installer enables it on
# every fresh install.
#
# Requires: pacman, repo-add, bsdtar (all part of a normal Arch host; the
# archiso package pulls them into the Docker build image). The download
# cache lives in mktemp's scratch space — set $TMPDIR if that is small.
# Usage: mk-bundle.sh <packages.list> <bundle-dir>
set -euo pipefail

usage() {
    echo "usage: $0 <packages.list> <bundle-dir>" >&2
    exit 2
}

(($# == 2)) || usage
list_path=$(realpath -- "$1")
bundle_dir=$(realpath -m -- "$2")
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

for command in pacman repo-add bsdtar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "error: required command is unavailable: $command" >&2
        exit 1
    }
done

mapfile -t wanted < <(grep -Ev '^\s*$|^#' "$list_path")
((${#wanted[@]} > 0)) || {
    echo "error: $list_path contains no packages" >&2
    exit 1
}
echo "bundling ${#wanted[@]} packages into $bundle_dir"

scratch=$(mktemp -d)
cleanup() {
    rm -rf -- "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/db/sync" "$scratch/cache"

# Scratch pacman config: releng's repos with multilib enabled (the
# installer always enables it in the target) against a known-good mirror.
releng_conf="$script_dir/../releng/pacman.conf"
scratch_conf="$scratch/pacman.conf"
mirrorlist="$scratch/mirrorlist"
printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$mirrorlist"
# drop the commented section headers, point the active repos at the
# scratch mirrorlist, then append the bundle-only multilib repo
sed -e '/^#\[/d' -e "s|^Include = .*|Include = $mirrorlist|" \
    -e 's|^\[core\]|DisableSandbox\n[core]|' \
    "$releng_conf" >"$scratch_conf"
cat >>"$scratch_conf" <<EOF

[multilib]
Include = $mirrorlist
EOF
# releng/pacman.conf is the source of truth; assert the scratch config
# ended up with exactly the four bundle repos before downloading anything.
for repo in core extra instant multilib; do
    grep -qx "\[$repo\]" "$scratch_conf" || {
        echo "error: [$repo] missing from the scratch pacman config" >&2
        exit 1
    }
done
if grep -q '^\[core-testing\]' "$scratch_conf"; then
    echo "error: testing repos must not be bundled" >&2
    exit 1
fi

pacman_args=(--config "$scratch_conf" --dbpath "$scratch/db" --cachedir "$scratch/cache")

# This script also runs independently of build.sh. Initialize the keyring
# selected by the scratch config before fetching the signed instant database.
if ((EUID == 0)); then
    "$script_dir/../../repo.sh" --bootstrap-key "$scratch_conf"
else
    sudo "$script_dir/../../repo.sh" --bootstrap-key "$scratch_conf"
fi

echo "syncing databases (scratch db: $scratch/db)"
pacman "${pacman_args[@]}" -Sy

echo "downloading packages (this downloads dependencies too)..."
pacman "${pacman_args[@]}" -Sw --noconfirm --quiet "${wanted[@]}"

shopt -s nullglob
pkgs=("$scratch/cache"/*.pkg.tar.zst)
((${#pkgs[@]} > 0)) || {
    echo "error: pacman downloaded nothing" >&2
    exit 1
}
echo "staging ${#pkgs[@]} package archives"

# Resolve each package to the first repo in config order that carries it —
# the same resolution order pacman itself uses.
pacman "${pacman_args[@]}" -Sl >"$scratch/repolist"
repo_of() {
    local pkg="$1" repo
    repo=$(awk -v p="$pkg" '$2 == p { print $1; exit }' "$scratch/repolist")
    [[ -n "$repo" ]] || {
        echo "error: cannot determine the repository of $pkg" >&2
        exit 1
    }
    printf '%s' "$repo"
}

declare -A staged_names=()
mkdir -p "$bundle_dir"
for pkg_file in "${pkgs[@]}"; do
    name=$(bsdtar -xOf "$pkg_file" .PKGINFO | sed -n 's/^pkgname = //p' | head -n 1)
    [[ -n "$name" ]] || {
        echo "error: no pkgname in ${pkg_file##*/}" >&2
        exit 1
    }
    if [[ -n "${staged_names[$name]+x}" ]]; then
        echo "error: $name staged twice (${staged_names[$name]} and ${pkg_file##*/})" >&2
        exit 1
    fi
    staged_names[$name]="${pkg_file##*/}"
    repo=$(repo_of "$name")
    dir="$bundle_dir/$repo/os/x86_64"
    mkdir -p "$dir"
    # cp (not ln): the pacman cache may live on a different filesystem
    cp "$pkg_file" "$dir/${pkg_file##*/}"
    # pacman -Sw fetches signatures for signed repos; ship them so offline
    # integrity checking equals the online path.
    if [[ -e "${pkg_file}.sig" ]]; then
        cp "${pkg_file}.sig" "$dir/${pkg_file##*/}.sig"
    fi
done

# Fail if the plan wants a package that pacman never delivered: a silent
# gap here is an install-time failure hours later on a machine with no net.
missing=0
for name in "${wanted[@]}"; do
    if [[ -z "${staged_names[$name]+x}" ]]; then
        echo "error: package not found in any bundled repo: $name" >&2
        missing=$((missing + 1))
    fi
done
((missing == 0)) || exit 1

echo "creating repository databases (repo-add needs the .db.tar.gz suffix)"
for repo in core extra multilib instant; do
    dir="$bundle_dir/$repo/os/x86_64"
    [[ -d "$dir" ]] || {
        echo "error: repo $repo was not staged at all" >&2
        exit 1
    }
    (cd "$dir" && repo-add "$repo.db.tar.gz" ./*.pkg.tar.zst)
done

# Mirror-region snapshot for the offline region question (~310 KB).
echo "snapshotting mirror region data"
"$script_dir/mk-region-data.sh" "$bundle_dir/regions"

cp "$list_path" "$bundle_dir/packages.list"

du -sh "$bundle_dir"
echo "bundle complete: $bundle_dir"
