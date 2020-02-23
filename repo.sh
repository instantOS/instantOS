#!/bin/bash

echo "adding instantOS repo"

if ! grep -q 'instantos\.surge\.sh' /etc/pacman.conf; then
    echo "[instant]" >>/etc/pacman.conf
    echo "SigLevel = Optional TrustAll" >>/etc/pacman.conf
    echo "Server = http://instantos.surge.sh" >>/etc/pacman.conf
fi