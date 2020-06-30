#!/bin/bash

###############################################################################
## add repo containing instantOS programs and required prebuilt aur programs ##
###############################################################################

echo "adding instantOS repo"

if ! uname -m | grep -q '^i'; then
    # default is 64 bit repo
    if ! grep -q 'instantos\.surge\.sh' /etc/pacman.conf; then
        echo "[instant]" >>/etc/pacman.conf
        echo "SigLevel = Optional TrustAll" >>/etc/pacman.conf
        echo "Server = http://instantos.surge.sh" >>/etc/pacman.conf
    else
        echo "instantOS repository already added"
    fi
else
    # 32 bit has a seperate repo (obviously)
    if ! grep -q 'instantos\.surge\.sh' /etc/pacman.conf; then
        echo "[instant]" >>/etc/pacman.conf
        echo "SigLevel = Optional TrustAll" >>/etc/pacman.conf
        echo "Server = http://instantos32.surge.sh" >>/etc/pacman.conf
    fi
fi
