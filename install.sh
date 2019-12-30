#!/usr/bin/env bash

#############################################
## installs all paperbenni suckless forks  ##
## made for personal use, so be warned ;)  ##
#############################################

echo "installing paperbenni's suckless suite"

source <(curl -s https://raw.githubusercontent.com/paperbenni/bash/master/import.sh)
pb install
pb git

gprogram() {
    wget "https://raw.githubusercontent.com/paperbenni/suckless/master/programs/$1"
    usrbin -f "$1"
}

if [ "$1" = "dotfiles" ]; then
    shift 1
    DOTFILES="True"
fi

THEME="${1:-dracula}"
echo "using theme $THEME"
[ -e ~/paperbenni ] || mkdir ~/paperbenni
echo "$THEME" >~/paperbenni/.theme

rm -rf suckless
mkdir suckless
cd suckless

gitclone dwm
gitclone dmenu
gitclone st

# needed for slock
if grep -q 'nobody' </etc/groups || grep -q 'nobody' </etc/group; then
    echo "nobody workaround not required"
else
    sudo groupadd nobody
fi

# add group and add user to group
ugroup() {
    if groups | grep -q "$1"; then
        echo "user is member of $1"
        return
    else
        sudo groupadd "$1"
        sudo gpasswd -a $USER $1
    fi
}

ugroup video
ugroup input

gitclone slock

# install cursors for themes
if ! [ -e ~/.icons/osx ]; then
    curl -s https://raw.githubusercontent.com/paperbenni/cursors/master/install.sh | bash
fi

# session for lightdm
wget https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
sudo mv dwm.desktop /usr/share/xsessions/

# x session wrapper
gprogram startdwm
# shutdown popup that breaks restart loop
gprogram sucklessshutdown

gprogram autoclicker

# dmenu run but in terminal emulator st
# only supported terminal apps (less to search through)
gprogram dmenu_run_st

gprogram dswitch
gprogram pbnotify

# for that extra kick when doingg a typo
gprogram sll

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

if cat /etc/os-release | grep -iq 'name.*arch' ||
    cat /etc/os-release | grep -iq 'name.*manjaro'; then
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
    pacinstall rofi
    pacinstall dunst

    pacinstall bash dash tmux
    pacinstall dialog
    pacinstall wget slop
    pacinstall acpi
    pacinstall cpio

    pacinstall ffmpeg
    pacinstall feh
    pacinstall mpv

    pacinstall wmctrl
    pacinstall xdotool
    pacinstall xrandr
    pacinstall xorg-xsetroot

    pacinstall conky
    pacinstall ranger
    pacinstall fzf
    pacinstall sl

    pacinstall xorg-fonts-misc
    pacinstall lxappearance

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther_launcher-1.12.0-1-x86_64.pkg.tar.xz"
        sudo pacman -U --noconfirm panther_launcher*.pkg.tar.xz
        rm panther_launcher*.pkg.tar.xz
    fi

fi

if ! [ ~/.local/share/fonts/symbola.ttf ]; then
    mkdir -p ~/.local/share/fonts
    cd ~/.local/share/fonts
    wget "http://symbola.surge.sh/symbola.ttf"
fi

cd

# ubuntu specific stuff
if grep -iq 'name.*ubuntu' </etc/os-release; then

    sudo apt-get update
    sudo apt-get upgrade -y

    aptinstall() {
        for i in "$@"; do
            { dpkg -l "$i" || command -v "$i"; } &>/dev/null && continue
            sudo apt-get install -y "$i"
        done
    }

    aptinstall compton

    aptinstall bash dash tmux
    aptinstall dialog
    aptinstall wget

    aptinstall slop
    aptinstall rofi
    aptinstall dunst

    aptinstall acpi
    aptinstall xrandr
    aptinstall x11-xserver-utils

    aptinstall ffmpeg
    aptinstall feh
    aptinstall mpv

    aptinstall cpio

    aptinstall fzf
    aptinstall ranger
    aptinstall conky
    aptinstall sl

    aptinstall lxappearance

    if ! command -v panther_launcher; then
        wget "https://www.rastersoft.com/descargas/panther_launcher/panther-launcher-xenial_1.12.0-ubuntu1_amd64.deb"
        sudo dpkg -i panther-launcher*.deb
        sudo apt-get install -fy
        rm panther-launcher*.deb
    fi
fi

# laptop specific stuff
if acpi | grep -q '[0-9]%'; then
    # config file to indicate being a laptop
    touch .cache/islaptop

    # fix tap to click not working with tiling wms
    if ! [ -e /etc/X11/xorg.conf.d/90-touchpad.conf ] ||
        ! cat /etc/X11/xorg.conf.d/90-touchpad.conf | grep -iq 'tapping.*"on"'; then

        sudo mkdir -p /etc/X11/xorg.conf.d && sudo tee /etc/X11/xorg.conf.d/90-touchpad.conf <<'EOF' 1>/dev/null
Section "InputClass"
        Identifier "touchpad"
        MatchIsTouchpad "on"
        Driver "libinput"
        Option "Tapping" "on"
EndSection

EOF
    fi

fi

curl -s "https://raw.githubusercontent.com/paperbenni/suckless/master/monitor.sh" | bash
cd

# three and four finger swipes on laptop
if ! command -v libinput-gestures &>/dev/null; then
    cd /tmp
    git clone --depth=1 https://github.com/bulletmark/libinput-gestures.git
    cd libinput-gestures
    sudo make install
    cd ..
    rm -rf libinput-gestures
fi

cd

# auto start script with dwm
ls .dwm &>/dev/null || mkdir .dwm
curl $LINK/autostart.sh >.dwm/autostart.sh
chmod +x .dwm/autostart.sh

# set up multi monitor config for dswitch
if ! [ -e paperbenni/ismultimonitor ]; then
    if xrandr | grep ' connected' | grep -Eo '[0-9]{3,}x' |
        grep -o '[0-9]*' | wc -l | grep '2'; then
        mkdir paperbenni &>/dev/null
        xrandr | grep ' connected' | grep -Eo '[0-9]{3,}x' |
            grep -o '[0-9]*' >paperbenni/ismultimonitor
        echo "$(wc -l paperbenni/ismultimonitor) monitors detected"
    else
        echo "not a multi monitor setup"
    fi
else
    echo "monitor config: "
    cat paperbenni/ismultimonitor
    echo ""
fi

cd

# install wmutils
if ! command -v pfw &>/dev/null; then
    cd /tmp
    if git clone --depth=1 https://github.com/wmutils/core.git; then
        cd core
        make
        sudo make install
        cd ..
        rm -rf core
    fi
fi

cd

# install win + a menus for shortcuts like screenshots and shutdown
curl https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash

# drag and drop x utility for ranger
if ! command -v dragon &>/dev/null; then
    cd /tmp
    git clone --depth=1 https://github.com/mwh/dragon.git
    cd dragon
    make
    make install
    cd ..
    rm -rf dragon
fi

cd
mkdir paperbenni &>/dev/null

# automatic wallpaper changer
# uses reddit r/wallpaper scraper
if [ "$2" = "rwall" ]; then
    cd /tmp
    gitclone rwallpaper
    cd rwallpaper
    mv rwallpaper.py ~/paperbenni/
    chmod +x wallpaper.sh
    mv wallpaper.sh ~/paperbenni/
    sudo pip3 install -r requirements.txt
    cd ..
    rm -rf rwallpaper
fi

cd

# set dwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=dwm' >>.dmrc
if [ -e /etc/lightdm/lightdm.conf ]; then
    sudo sed -i 's/^user-session=.*/user-session=dwm/g' /etc/lightdm/lightdm.conf
fi

# install things like fonts or gtk theme
if ! [ -e .config/paperthemes/$THEME.txt ]; then
    echo "installing theme"
    curl -s "https://raw.githubusercontent.com/paperbenni/suckless/master/themes/$THEME.sh" | bash
    mkdir .config/paperthemes
    touch .config/paperthemes/$THEME.txt
else
    echo "theme installation already found"
fi

# fix java gui appearing empty on dwm
if ! grep 'dwm' </etc/profile; then
    echo "fixing java windows for dwm in /etc/profile"
    echo '# fix dwm java windows' | sudo tee -a /etc/profile
    echo 'export _JAVA_AWT_WM_NONREPARENTING=1' | sudo tee -a /etc/profile
else
    echo "java workaround already applied"
fi
