#!/bin/bash

######################################################
## installs all system wide programs for instantOS  ##
######################################################

if ! [ $(whoami) = "root" ]; then
    echo "please run this as root"
    exit 1
fi

mkdir -p /opt/instantos

# add group and add users to group
ugroup() {
    groupadd "$1"
    for USER in $(ls /home/ | grep -v '+'); do
        sudo gpasswd -a $USER $1
    done
}

ugroup video
ugroup input

RAW="https://raw.githubusercontent.com"

# fetches and installs program from this repo
gprogram() {
    echo "installing $1"
    curl -s "$RAW/paperbenni/suckless/master/programs/$1" | sudo tee /usr/bin/$1 &>/dev/null
    chmod +x /usr/bin/"$1"
}

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

# for that extra kick when doingg a typpo
gprogram sll

# adds permanent global environment variable
addenv() {
    [ -e /etc/environment ] || touch /etc/environment
    if [ "$1" = "-f" ]; then
        local FORCE="true"
        shift 1
    fi

    if grep -q "$1=" /etc/environment; then
        if [ -z "$FORCE" ]; then
            echo "key already existing"
            return 1
        else
            sed -i "s/$1=.*/$1=$2/g" /etc/environment
        fi
    else
        echo "$1=$2" >>/etc/environment
    fi
}

addenv -f "QT_QPA_PLATFORMTHEME" "qt5ct"
command -v nvim &>/dev/null && addenv -f "EDITOR" "$(which nvim)"

# needed for instantLOCK
if grep -q 'nobody' </etc/groups || grep -q 'nobody' </etc/group; then
    echo "nobody workaround not required"
else
    sudo groupadd nobody
fi

# fix java gui appearing empty on instantWM
if ! grep -q 'instantwm' </etc/profile; then
    echo "fixing java windows for instantwm in /etc/profile"
    echo '# fix instantwm java windows' >>/etc/profile
    echo 'export _JAVA_AWT_WM_NONREPARENTING=1' >>/etc/profile
else
    echo "java workaround already applied"
fi

if [ -e /etc/lightdm/lightdm.conf ]; then
    sudo sed -i 's/^user-session=.*/user-session=instantwm/g' /etc/lightdm/lightdm.conf
fi

mkdir /tmp/instantinstall
cd /tmp/instantinstall

# session for lightdm
wget -q $RAW/paperbenni/suckless/master/instantwm.desktop
sudo mv instantwm.desktop /usr/share/xsessions/
sudo chmod 644 /usr/share/xsessions/instantwm.desktop

# laptop specific stuff
if acpi | grep -q '[0-9]%'; then

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

        # three and four finger swipes on laptop
        if ! command -v libinput-gestures &>/dev/null; then
            git clone --depth=1 https://github.com/bulletmark/libinput-gestures.git
            cd libinput-gestures
            sudo make install
            cd ..
            rm -rf libinput-gestures
        fi
    fi
else
    echo "system is on a desktop"
fi

iclone() {
    echo "cloning $1"
    gitclone instantOS/$@ &>/dev/null
}

rm -rf /tmp/instantos &>/dev/null
mkdir /tmp/instantos
cd /tmp/instantos

iclone instantWM
iclone instantMENU
iclone instantLOCK

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

cd /tmp
rm -rf instantos
