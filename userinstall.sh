#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

echo "installing instantOS tools"

RAW="https://raw.githubusercontent.com"
source <(curl -s $RAW/paperbenni/bash/master/import.sh)
pb install
pb git

LINK="$RAW/paperbenni/suckless/master"

curl "$LINK/termprograms.txt" >~/.cache/termprograms.txt

if ! [ ~/.local/share/fonts/symbola.ttf ]; then
    mkdir -p ~/.local/share/fonts
    cd ~/.local/share/fonts
    echo "installing symbola font"
    wget -q "http://symbola.surge.sh/symbola.ttf"
fi

cd

# laptop specific stuff
if acpi | grep -q '[0-9]%'; then
    # config file to indicate being a laptop
    touch .cache/islaptop
else
    curl -s "$RAW/paperbenni/suckless/master/monitor.sh" | bash
fi

cd

# auto start script with instantWM
ls .instantos &>/dev/null || mkdir .instantos
curl $LINK/autostart.sh >.instantos/autostart.sh
chmod +x .instantos/autostart.sh

cd /tmp
# drag and drop x utility for ranger
if ! command -v dragon &>/dev/null; then
    cd /tmp
    git clone --depth=1 https://github.com/mwh/dragon.git &>/dev/null
    cd dragon
    make
    make install
    cd ..
    rm -rf dragon
fi

cd
mkdir -p paperbenni/notifications &>/dev/null

# gets executed by dunst on notification
curl "$RAW/paperbenni/suckless/master/programs/dunsttrigger" >~/paperbenni/notifications/dunsttrigger
chmod +x ~/paperbenni/notifications/dunsttrigger
wget -O ~/paperbenni/notifications/notification.ogg "https://notificationsounds.com/notification-sounds/me-too-603/download/ogg"

cd
mkdir instantos/wallpapers
curl -s "$RAW/instantOS/instantWALLPAPER/master/wall.sh" >intantos/wallpapers/wall.sh
chmod +x intantos/wallpapers/wall.sh

# set instantwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=instantwm' >>.dmrc
