#!/bin/bash

source <(curl -Ls https://git.io/JerLG)
pb git
pb gtk

# gtk theme
if themeexists materiacula &>/dev/null && icons_exist materiacula &>/dev/null; then
    echo "gtk theme dracula found"
else
    gitclone materiacula
    cd materiacula
    bash install.sh
    cd ..
    rm -rf materiacula
fi

gtktheme materiacula
gtkicons materiacula
gtkfont "Roboto 10"

setcursor paper

rofitheme dracula
dunsttheme dracula

curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/monaco.sh" | bash
curl -s "https://raw.githubusercontent.com/paperbenni/dotfiles/master/fonts/roboto.sh" | bash
