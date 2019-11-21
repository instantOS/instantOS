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
    usrbin "$1"
}

if [ "$1" = "dotfiles" ]; then
    shift 1
    DOTFILES="True"
fi

THEME="${1:-dracula}"

rm -rf suckless
mkdir suckless
cd suckless

gclone dwm
gclone dmenu
gclone st

# needed for slock
if grep -q 'nobody' </etc/groups; then
    sudo groupadd nobody
fi
gclone slock

# session for lightdm
wget https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
sudo mv dwm.desktop /usr/share/xsessions/

# x session wrapper
gprogram startdwm
# shutdown popup that breaks restart loop
gprogram sucklessshutdown

gprogram autoclicker
# deadcenter toggle script
gprogram deadcenter

# dmenu run but in terminal emulator st
# only supported terminal apps (less to search through)
gprogram dmenu_run_st

curl "$LINK/termprograms.txt" >~/.cache/termprograms.txt

for FOLDER in ./*; do
    if ! [ -d "$FOLDER" ]; then
        echo "skipping $FOLDER"
        continue
    fi
    pushd "$FOLDER"
    if ! [ -e build.sh ]; then
        rm config.h
        make
        sudo make install
    else
        chmod +x ./build.sh
        ./build.sh "$THEME"
    fi
    popd
done

# install dotfiles like bash,git and tmux config
if [ -n "$DOTFILES" ]; then
    curl https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
fi

LINK="https://raw.githubusercontent.com/paperbenni/suckless/master"

if cat /etc/os-release | grep -i 'arch'; then
    pacinstall() {
        for i in "$@"; do
            { pacman -iQ "$i" || command -v "$i"; } &>/dev/null && continue
            sudo pacman -S --noconfirm "$i"
        done
    }
    echo "setting up arch specific stuff"

    sudo pacman -Syu --noconfirm

    # utilities
    pacinstall picom
    pacinstall bash dash
    pacinstall wget slop
    pacinstall ffmpeg
    pacinstall dmidecode

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther_launcher-1.12.0-1-x86_64.pkg.tar.xz"
        sudo pacman -U --noconfirm panther_launcher*.pkg.tar.xz
        rm panther_launcher*.pkg.tar.xz
    fi

fi

if sudo dmidecode --string chassis-type | grep -iq 'laptop'; then
    touch .cache/islaptop
fi

# ubuntu specific stuff
if grep -iq 'ubuntu' </etc/os-release; then

    sudo apt-get update
    sudo apt-get upgrade -y

    # utilities
    aptinstall compton
    aptinstall bash dash
    aptinstall wget slop
    aptinstall ffmpeg

    aptinstall() {
        for i in "$@"; do
            { dpkg -l "$i" || command -v "$i"; } &>/dev/null && continue
            sudo apt-get install -y "$i"
        done
    }

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther-launcher-xenial_1.12.0-ubuntu1_amd64.deb"
        sudo dpkg -i panther-launcher*.deb
        sudo apt-get install -fy
        rm panther-launcher*.deb
    fi
fi

# auto start script with dwm
ls ~/.dwm || mkdir ~/.dwm
curl $LINK/autostart.sh >~/.dwm/autostart.sh

# notification program for deadd-center
if ! command -v notify-send.py &>/dev/null; then
    git clone --depth=2 https://github.com/phuhl/notify-send.py
    cd notify-send.py
    sudo pip2 install notify2
    sudo python3 setup.py install
    cd ..
    sudo rm -rf notify-send.py
fi

mkdir -p ~/.config/deadd
curl $LINK/deadd.conf >~/.config/deadd/deadd.conf

# install window switcher
curl "$LINK/dswitch" | sudo tee /usr/local/bin/dswitch
sudo chmod +x /usr/local/bin/dswitch

# install win + a menus for shortcuts like screenshots and shutdown
curl https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash

## notification center ##
# remove faulty installation
sudo rm /usr/bin/deadd &>/dev/null
sudo rm /usr/bin/deadcenter &>/dev/null

# main binary
echo "installing deadd"
wget -q $LINK/bin/deadd.xz
xz -d deadd.xz
sleep 0.1
sudo mv deadd /usr/bin/deadd
sudo chmod +x /usr/bin/deadd

mkdir ~/paperbenni &>/dev/null

# automatic wallpaper changer
gclone rwallpaper
cd rwallpaper
mv rwallpaper.py ~/paperbenni/
chmod +x wallpaper.sh
mv wallpaper.sh ~/paperbenni/
sudo pip3 install -r requirements.txt
cd ..
rm -rf rwallpaper

# install things like fonts or gtk theme
if ! [ -e ~/.config/paperthemes/$THEME.txt ]; then
    echo "installing theme"
    curl -s "https://raw.githubusercontent.com/paperbenni/suckless/master/themes/$THEME.sh" | bash
    mkdir ~/.config/paperthemes
    touch ~/.config/paperthemes/$THEME.txt
else
    echo "theme installation already found"
fi

# fix java on dwm
if ! grep 'dwm' </etc/profile; then
    echo "fixing java windows for dwm in /etc/profile"
    echo '# fix dwm java windows' | sudo tee -a /etc/profile
    echo 'export _JAVA_AWT_WM_NONREPARENTING=1' | sudo tee -a /etc/profile
else
    echo "java workaround already applied"
fi
