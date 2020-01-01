#!/bin/bash

# installs dependencies for paperbenni suckless

LINK="https://raw.githubusercontent.com/paperbenni/suckless/master"

if cat /etc/os-release | grep -iq 'name.*arch' ||
    cat /etc/os-release | grep -iq 'name.*manjaro'; then
    pacinstall() {
        for i in "$@"; do
            { pacman -iQ "$i" || command -v "$i" &>/dev/null; } &>/dev/null && continue
            sudo pacman -S --noconfirm "$i"
        done
    }
    echo "setting up arch specific stuff"

    sudo pacman -Syu --noconfirm

    # utilities
    pacinstall picom
    pacinstall rofi
    pacinstall dunst
    pacinstall tar

    pacinstall bash dash tmux
    pacinstall neovim
    pacinstall dialog
    pacinstall wget slop
    pacinstall acpi
    pacinstall cpio

    aptinstall git
    aptinstall subversion
    aptinstall neovim

    pacinstall ffmpeg
    pacinstall feh
    pacinstall mpv

    pacinstall wmctrl
    pacinstall xdotool
    pacinstall xrandr
    pacinstall xorg-xsetroot

    pacinstall conky
    pacinstall ranger
    pacinstall fzf
    pacinstall sl

    pacinstall xorg-fonts-misc
    pacinstall lxappearance
    pacinstall qt5ct

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther_launcher-1.12.0-1-x86_64.pkg.tar.xz"
        sudo pacman -U --noconfirm panther_launcher*.pkg.tar.xz
        rm panther_launcher*.pkg.tar.xz
    fi

fi

# ubuntu specific stuff
if grep -iq 'name.*ubuntu' </etc/os-release; then

    sudo apt-get update
    sudo apt-get upgrade -y

    aptinstall() {
        for i in "$@"; do
            { dpkg -l "$i" || command -v "$i" &>/dev/null; } &>/dev/null && continue
            sudo apt-get install -y "$i"
        done
    }

    aptinstall compton

    aptinstall git
    aptinstall subversion
    aptinstall tar

    aptinstall bash dash tmux
    aptinstall dialog
    aptinstall wget

    aptinstall slop
    aptinstall rofi
    aptinstall dunst

    aptinstall acpi
    aptinstall xrandr
    aptinstall x11-xserver-utils

    aptinstall ffmpeg
    aptinstall feh
    aptinstall mpv
    aptinstall conky

    aptinstall cpio

    aptinstall fzf
    aptinstall ranger
    aptinstall sl

    aptinstall qt5ct
    aptinstall lxappearance

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther-launcher-xenial_1.12.0-ubuntu1_amd64.deb"
        sudo dpkg -i panther-launcher*.deb
        sudo apt-get install -fy
        rm panther-launcher*.deb
    fi
fi
