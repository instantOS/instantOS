#!/bin/bash
# todo
source <(curl -Ls https://git.io/JerLG)
pb git
pb gtk
pb unpack

mkdir /tmp/manjarotheme
cd /tmp/manjarotheme

if ! themeexists matcha; then
    git clone --depth=1 https://github.com/vinceliuice/matcha.git
    cd matcha
    ./Install
    cd ..
    rm -rf matcha
fi

if ! icons_exist "Papirus-Maia"; then
    git clone --depth=1 https://github.com/Ste74/papirus-maia-icon-theme.git
    cd papirus-maia-icon-theme
    mkdir ~/.icons &>/dev/null
    mv Papirus* ~/.icons
    cd ..
    rm -rf papirus-maia-icon-theme

fi
