#!/bin/bash

###############################################################################
## add repo containing instantOS programs and required prebuilt aur programs ##
###############################################################################

whoami | grep -q 'root' || { echo "please run this as root" && exit 1; }

echo "adding instantOS repository list"

# Pinned to an instantCLI release tag, not a branch: this is a build input, and
# a moving ref breaks installs whenever instantCLI reorganises its source tree.
# Keep in sync with packages/instantos-mirrorlist/PKGBUILD in instantOS/packages.
MIRRORLIST_URL="https://raw.githubusercontent.com/instantOS/instantCLI/v0.14.23/src/arch/instantmirrorlist"
MIRRORLIST_PATH="/etc/pacman.d/instantmirrorlist"

addrepo() {

    # Fetch before touching pacman.conf. `> $MIRRORLIST_PATH` would truncate the
    # file before curl runs, so a failed download left a zero-byte mirrorlist
    # that pacman.conf still pointed [instant] at. Download to a temporary file
    # and move it into place only once it is known to be good.
    tmpmirrorlist=$(mktemp) || return 1
    if ! curl -fsSL "$MIRRORLIST_URL" -o "$tmpmirrorlist"; then
        echo "could not fetch the instantOS mirror list from $MIRRORLIST_URL" >&2
        echo "leaving $MIRRORLIST_PATH and /etc/pacman.conf unchanged" >&2
        rm -f "$tmpmirrorlist"
        return 1
    fi

    install -Dm644 "$tmpmirrorlist" "$MIRRORLIST_PATH" || {
        rm -f "$tmpmirrorlist"
        return 1
    }
    rm -f "$tmpmirrorlist"

    if grep -q '\[instant\]' /etc/pacman.conf; then
        echo "removing old mirrors"
        sed -i '/^\[instant\]/,+2d' /etc/pacman.conf
    fi

    echo "adding $1 repo"
    {
        echo "[instant]"
        echo "SigLevel = Optional TrustAll"
        echo "Include = $MIRRORLIST_PATH"
    } >>/etc/pacman.conf

    # allow choosing subdirectory for testing purposes
    if [ -n "$CUSTOMINSTANTREPO" ]; then
        sed -i 's/.*instantos.io\/packages.*/Server = https:\/\/instantos.io\/packages\/'"$CUSTOMINSTANTREPO"'/g' "$MIRRORLIST_PATH"
    fi

}

if uname -m | grep -q '^x'; then
    # default is 64 bit repo
    addrepo amd64 || exit 1
elif uname -m | grep 'arm'; then
    echo "no official arm repo yet"
    exit
else
    echo "no suitable repo for architecture found"
    exit 1
fi

echo "the instantOS pacman repository has been added to your system"
echo "run the following to install all instantOS packages"
echo "sudo pacman -Syu && sudo pacman -S instantos instantdepend"
echo "installing on non-instantOS systems only has inofficial support"
echo ""
