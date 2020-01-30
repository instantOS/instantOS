#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd "$HOME"

echo "installing instantOS tools"

RAW="https://raw.githubusercontent.com"
source <(curl -s $RAW/paperbenni/bash/master/import.sh)
pb install
pb git

LINK="$RAW/instantos/instantos/master"

if ! [ ~/.local/share/fonts/symbola.ttf ]; then
    mkdir -p .local/share/fonts
    cd .local/share/fonts
    echo "installing symbola font"
    wget -q "http://symbola.surge.sh/symbola.ttf"
fi

cd "$HOME"

# laptop specific stuff
if acpi | grep -q '[0-9]%' &>/dev/null; then
    # config file to indicate being a laptop
    touch .cache/islaptop
fi

cd
mkdir -p instantos/notifications &>/dev/null
cd instantos/notifications

if ! [ -e notification.ogg ]; then
    wget -qO notification.ogg "https://notificationsounds.com/notification-sounds/me-too-603/download/ogg"
fi

cd ~/instantos
rm -rf wallpapers
mkdir wallpapers

# set instantwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=instantwm' >>.dmrc
