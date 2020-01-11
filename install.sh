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

# fetches and installs program from this repo
gprogram() {
    echo "installing $1"
    wget -q "$RAW/paperbenni/suckless/master/programs/$1"
    usrbin -f "$1"
}

gclone() {
    echo "cloning $1"
    gitclone $@ &>/dev/null
}

iclone() {
    echo "cloning $1"
    gitclone instantOS/$@ &>/dev/null
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

iclone instantWM

#iclone instantMENU // weiter

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

# session for lightdm
wget -q $RAW/paperbenni/suckless/master/instantwm.desktop
sudo mv instantwm.desktop /usr/share/xsessions/

# x session wrapper
gprogram startinstantwm
# shutdown popup that breaks restart loop
gprogram instantshutdown

gprogram autoclicker

# dmenu run but in terminal emulator st
# only supported terminal apps (less to search through)
gprogram instantterm

gprogram instantswitch
gprogram instantnotify

# for that extra kick when doingg a typo
gprogram sll

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

curl -s "$RAW/paperbenni/suckless/master/monitor.sh" | bash
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

# auto start script with instantWM
ls .instantos &>/dev/null || mkdir .instantos
curl $LINK/autostart.sh >.instantos/autostart.sh
chmod +x .instantos/autostart.sh

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
curl -s $RAW/paperbenni/menus/master/install.sh | bash

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
curl -s "$RAW/instantOS/instantWALLPAPER/master/wall.sh" > intantos/wallpapers/wall.sh
chmod +x intantos/wallpapers/wall.sh

# set instantwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=instantwm' >>.dmrc
if [ -e /etc/lightdm/lightdm.conf ]; then
    sudo sed -i 's/^user-session=.*/user-session=instantwm/g' /etc/lightdm/lightdm.conf
fi

# fix java gui appearing empty on instantWM
if ! grep -q 'instantwm' </etc/profile; then
    echo "fixing java windows for instantwm in /etc/profile"
    echo '# fix instantwm java windows' | sudo tee -a /etc/profile
    echo 'export _JAVA_AWT_WM_NONREPARENTING=1' | sudo tee -a /etc/profile
else
    echo "java workaround already applied"
fi
