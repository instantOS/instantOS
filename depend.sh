#!/bin/bash

# installs dependencies for instantOS

export LINK="https://raw.githubusercontent.com/instantos/instantos/master"

# install on arch based system
pacinstall() {
    for i in "$@"; do
        { pacman -iQ "$i" || command -v "$i"; } &>/dev/null && continue
        echo "Installing $i"
        sudo pacman -S --noconfirm "$i" &>/dev/null
    done
}

if ! command -v pacman &>/dev/null; then
    echo "distro not supported"
    exit
fi

# cross distro install command
ipkg() {
    pacinstall "$@"
}

# on arch instantARCH takes care of this
if cat /etc/os-release | grep -qi 'manjaro'; then
    if hwinfo --gfxcard --short | grep -iE 'nvidia.*(gtx|rtx|titan)'; then
        echo "installing nvidia graphics drivers"
        sudo mhwd -a pci nonfree 0300
        if grep -Eiq 'instantos|manjaro' /etc/os-release; then
            if pacman -iQ linux54; then
                pacinstall linux54-nvidia-440x
            fi

            if pacman -iQ linux419; then
                pacinstall linux419-nvidia-440xx
            fi
        else
            if pacman -iQ linux-lts; then
                pacinstall nvidia-lts
            fi
            pacinstall nvidia
        fi
    fi
else
    pacinstall xdg-desktop-portal-gtk
fi
