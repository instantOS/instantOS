#!/usr/bin/env bash

#############################################
## installs all paperbenni suckless forks  ##
## made for personal use, so be warned ;)  ##
#############################################

echo "installing paperbenni's suckless suite"

source <(curl -s https://raw.githubusercontent.com/paperbenni/bash/master/import.sh)
pb install

pinstall dash slop ffmpeg wmctrl

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

    # install notification-center
    if ! command -v deadd-notification-center; then
        wget $LINK/bin/deadd.pkg.tar.xz
        sudo pacman --noconfirm -U deadd.pkg.tar.xz
        rm deadd.pkg.tar.xz
    fi

fi

mkdir -p ~/.config/deadd
curl $LINK/deadd.conf >~/.config/deadd/deadd.conf

curl "$LINK/dswitch" | sudo tee /usr/local/bin/dswitch
sudo chmod +x /usr/local/bin/dswitch

git clone https://github.com/phuhl/notify-send.py
cd notify-send.py
sudo pip install notify2
sudo python setup.py install
cd ..
rm -rf notify-send.py

# install win + a menus for screenshots
curl https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash
