#!/bin/bash
# central installer script for pb suckless

if cat /etc/os-release | grep -Eiq 'name.*(arch|manjaro|ubuntu)'; then

curl -s "https://raw.githubusercontent.com/instantOS/instantLOGO/master/ascii.txt"

else
    echo "distro not supported"
    echo "supported are: Arch, Manjaro, Ubuntu"
    exit
fi

echo "installing dependencies"
curl -s https://raw.githubusercontent.com/paperbenni/suckless/master/depend.sh | bash
echo "installing suckless tools"
curl -s https://raw.githubusercontent.com/paperbenni/suckless/master/install.sh | bash
echo "installing theme"
export THEME=${1:-dracula}
curl -s "https://raw.githubusercontent.com/instantOS/instantTHEMES/master/$THEME.sh" | bash

echo "installing dotfiles"
curl -s https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
