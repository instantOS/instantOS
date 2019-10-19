#!/usr/bin/env bash

#############################################
## installs all paperbenni suckless forks  ##
## made for personal use, so be warned ;)  ##
#############################################

echo "installing paperbenni's suckless suite"

source <(curl -s https://raw.githubusercontent.com/paperbenni/bash/master/import.sh)
pb install

# pinstall dash slop ffmpeg wmctrl

gclone() {
    git clone --depth=1 https://github.com/paperbenni/"$1".git
}

gprogram() {
    wget "https://raw.githubusercontent.com/paperbenni/suckless/master/programs/$1"
    sudo mv $1 /bin/
    sudo chmod +x /bin/$1
}

mkdir -p ~/.local/share/fonts

pushd ~/.local/share/fonts
if ! [ -e monaco.ttf ]; then
    wget https://github.com/todylu/monaco.ttf/raw/master/monaco.ttf
fi
popd

rm -rf ~/suckless
mkdir ~/suckless
cd ~/suckless

gclone dwm
gclone dmenu
gclone st
gclone slock

# session for lightdm
wget https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
sudo mv dwm.desktop /usr/share/xsessions/

gprogram startdwm
gprogram sucklessshutdown

for FOLDER in ./*; do
    if ! [ -d "$FOLDER" ]; then
        echo "skipping $FOLDER"
        continue
    fi
    pushd "$FOLDER"
    rm config.h
    make
    sudo make install
    popd
done

if ! [ -z "$1" ]; then
    curl https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
fi

# install window switcher
LINK="https://raw.githubusercontent.com/paperbenni/suckless/master"

if cat /etc/os-release | grep -i 'arch'; then
    echo "setting up arch specific stuff"
    # auto start script with dwm
    ls ~/.dwm || mkdir ~/.dwm
    curl $LINK/autostart.sh >~/.dwm/autostart.sh
    if ! command -v compton; then
        sudo pacman --noconfirm -S compton
    fi

fi

# install notification-center
if ! command -v deadd; then
    wget $LINK/bin/deadd.xz
    wget $LINK/bin/deaddcenter
    xz -d deadd.xz
    sudo mv deadd /usr/bin/deadd
    sudo chmod +x /usr/bin/deadd
    sudo mv deaddcenter /usr/bin/deadd
    sudo chmod +x /usr/bin/deaddcenter
fi

# notification program for deadd-center
git clone --depth=2 https://github.com/phuhl/notify-send.py
cd notify-send.py
sudo pip install notify2
sudo python setup.py install
cd ..
sudo rm -rf notify-send.py

mkdir -p ~/.config/deadd
curl $LINK/deadd.conf >~/.config/deadd/deadd.conf

curl "$LINK/dswitch" | sudo tee /usr/local/bin/dswitch
sudo chmod +x /usr/local/bin/dswitch

# install win + a menus for screenshots
curl https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash
