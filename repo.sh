#!/bin/bash

###############################################################################
## add repo containing instantOS programs and required prebuilt aur programs ##
###############################################################################

echo "adding instantOS repo"

addrepo() {
    if ! grep -q "$1"'\.surge\.sh' /etc/pacman.conf; then
        echo "adding $1 repo"
        echo "[instant]" >>/etc/pacman.conf
        echo "SigLevel = Optional TrustAll" >>/etc/pacman.conf
        echo "Server = http://$1.surge.sh" >>/etc/pacman.conf
    else
        echo "instantOS $1 repository already added"
    fi

}

if uname -m | grep -q '^x'; then
    # default is 64 bit repo
    addrepo instantos
elif uname -m | grep 'arm'; then
    addrepo instantosarm
elif uname -m | grep '^i'; then
    addrepo instantos32
else
    echo "no suitable repo for architecture found"
fi
