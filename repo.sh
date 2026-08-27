#!/bin/bash

###############################################################################
## add repo containing instantOS programs and required prebuilt aur programs ##
###############################################################################

whoami | grep -q 'root' || { echo "please run this as root" && exit 1; }

echo "adding instantOS repository list"

addrepo() {

    if grep -q '\[instant\]' /etc/pacman.conf; then
        echo "removing old mirrors"
        sed -i '/^\[instant\]/,+2d' /etc/pacman.conf
    fi

    echo "adding $1 repo"
    {
        echo "[instant]"
        echo "SigLevel = Optional TrustAll"
        echo "Include = /etc/pacman.d/instantmirrorlist"
    } >>/etc/pacman.conf

    curl -fsSL https://raw.githubusercontent.com/instantOS/instantCLI/main/src/common/instantmirrorlist >/etc/pacman.d/instantmirrorlist

    # allow choosing subdirectory for testing purposes
    if [ -n "$CUSTOMINSTANTREPO" ]; then
        sed -i 's/.*instantos.io\/packages.*/Server = https:\/\/instantos.io\/packages\/'"$CUSTOMINSTANTREPO"'/g' /etc/pacman.d/instantmirrorlist
    fi

}

if uname -m | grep -q '^x'; then
    # default is 64 bit repo
    addrepo amd64
elif uname -m | grep 'arm'; then
    echo "no official arm repo yet"
    exit
    addrepo instantosarm
else
    echo "no suitable repo for architecture found"
fi

echo "the instantOS pacman repository has been added to your system"
echo "run the following to install all instantOS packages"
echo "sudo pacman -Syu && sudo pacman -S instantos instantdepend"
echo "installing on non-instantOS systems only has inofficial support"
echo ""
