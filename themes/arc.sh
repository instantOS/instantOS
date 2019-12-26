#!/bin/bash

source <(curl -Ls https://git.io/JerLG)
pb git
pb config
pb gtk

# gtk theme
if ! themeexists Arc; then
    command -v pacman && sudo pacman -S --noconfirm arc-gtk-theme
    command -v apt-get && sudo apt-get install -y arc-theme
fi
gtktheme Arc

# gtk icons
if ! icons_exist Papirus; then
    pushd .
    cd
    gitclone PapirusDevelopmentTeam/papirus-icon-theme
    cd papirus-icon-theme
    ./install.sh
    cd ..
    rm -rf papirus-icon-theme
    popd
fi

gtkicons Papirus
setcursor elementary

# rofi setup
mkdir -p ~/.config/rofi &>/dev/null
[ -e ~/.config/rofi/arc.rasi ] ||
    curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/rofi/arc.rasi" >~/.config/rofi/arc.rasi
echo 'rofi.theme: ~/.config/rofi/arc.rasi' >~/.config/rofi/config

curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/sourcecodepro.sh" | bash
curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/roboto.sh" | bash
echo "done installing arc theme"
