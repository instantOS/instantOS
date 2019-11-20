#!/bin/bash

source <(curl -Ls https://git.io/JerLG)
pb git
pb config

# gtk theme
if ! themeexists Arc; then
    command -v pacman && sudo pacman -S --noconfirm arc-gtk-theme
    command -v apt-get && sudo apt-get install -y arc-theme
fi
gtktheme Arc

# gtk icons
if ! icons_exist Papirus; then
    gclone PapirusDevelopmentTeam/papirus-icon-theme
    cd papirus-icon-theme
    ./install.sh
    cd ..
fi
gtkicons Papirus

curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/sourcecodepro.sh" | bash
curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/roboto.sh" | bash