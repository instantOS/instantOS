#!/bin/bash

###############################################################################
## add repo containing instantOS programs and required prebuilt aur programs ##
###############################################################################


whoami | grep -q 'root' || { echo "please run this as root" && exit 1
}

echo "adding instantOS repos"

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
    }>>/etc/pacman.conf

    if [ -e /usr/share/instantutils/mirrors/"$1" ]; then
        cat /usr/share/instantutils/mirrors/"$1" >/etc/pacman.d/instantmirrorlist
    else
        curl -s https://raw.githubusercontent.com/instantOS/instantOS/master/mirrors/"$1" >/etc/pacman.d/instantmirrorlist
    fi

}

if uname -m | grep -q '^x'; then
    # default is 64 bit repo
    addrepo amd64
elif uname -m | grep 'arm'; then
    echo "no official arm repo yet"
    exit
    addrepo instantosarm
elif uname -m | grep '^i'; then
    echo "no official 32 bit repo yet"
    exit
    addrepo instantos32
else
    echo "no suitable repo for architecture found"
fi

echo "done adding the instantos repository"

