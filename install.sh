#!/usr/bin/env bash

#############################################
## installs all paperbenni suckless forks  ##
## made for personal use, so be warned ;)  ##
#############################################

echo "installing paperbenni's suckless suite"

source <(curl -s https://raw.githubusercontent.com/paperbenni/bash/master/import.sh)
pb install
pb git

LINK="https://raw.githubusercontent.com/paperbenni/suckless/master"

# fetches and installs program from this repo
gprogram() {
    echo "installing $1"
    wget -q "https://raw.githubusercontent.com/paperbenni/suckless/master/programs/$1"
    usrbin -f "$1"
}

gclone() {
    echo "cloning $1"
    gitclone $@ &>/dev/null
}

# adds permanent global environment variable
addenv() {
    [ -e /etc/environment ] || sudo touch /etc/environment
    if [ "$1" = "-f" ]; then
        local FORCE="true"
        shift 1
    fi

    if grep -q "$1=" /etc/environment; then
        if [ -z "$FORCE" ]; then
            echo "key already there"
            return 1
        else
            sudo sed -i "s/$1=.*/$1=$2/g" /etc/environment
        fi
    else
        echo "$1=$2" | sudo tee -a /etc/environment
    fi
}

addenv -f "QT_QPA_PLATFORMTHEME" "qt5ct"
command -v nvim &>/dev/null && addenv -f "EDITOR" "$(which nvim)"

THEME="${1:-dracula}"
echo "using theme $THEME"
[ -e ~/paperbenni ] || mkdir ~/paperbenni
echo "$THEME" >~/paperbenni/.theme

rm -rf suckless
mkdir suckless
cd suckless

gclone dwm
gclone dmenu
gclone st

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

gclone slock

# install cursors for themes
if ! [ -e ~/.icons/osx ]; then
    curl -s https://raw.githubusercontent.com/paperbenni/cursors/master/install.sh | bash
fi

# session for lightdm
wget -q https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
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
        make &>/dev/null
        sudo make install &>/dev/null
    else
        chmod +x ./build.sh
        ./build.sh "$THEME" &>/dev/null
    fi
    popd
done

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
        grep -o '[0-9]*' | wc -l | grep -q '2'; then
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
curl -s https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash

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
curl "https://raw.githubusercontent.com/paperbenni/suckless/master/programs/dunsttrigger" >~/paperbenni/notifications/dunsttrigger
chmod +x ~/paperbenni/notifications/dunsttrigger

# automatic wallpaper changer
# uses reddit r/wallpaper scraper
if [ "$2" = "rwall" ]; then
    cd /tmp
    gclone rwallpaper
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
if ! grep -q 'dwm' </etc/profile; then
    echo "fixing java windows for dwm in /etc/profile"
    echo '# fix dwm java windows' | sudo tee -a /etc/profile
    echo 'export _JAVA_AWT_WM_NONREPARENTING=1' | sudo tee -a /etc/profile
else
    echo "java workaround already applied"
fi
