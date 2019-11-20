#!/bin/bash

source <(curl -Ls https://git.io/JerLG)
pb git
pb gtk

# gtk theme
if ! themeexists Mojave-light; then
    gclone vinceliuice/Mojave-gtk-theme
    cd Mojave-gtk-theme
    ./install.sh
    cd ..
fi
gtktheme Mojave-light

# gtk icons
if ! icons_exist McMojave-circle; then
    gclone vinceliuice/McMojave-circle
    cd McMojave-circle
    ./install.sh
    cd ..
fi
gtkicons McMojave-circle

curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/monaco.sh" | bash
