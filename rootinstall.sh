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
    groupadd "$1" &>/dev/null
    for USER in $(ls /home/ | grep -v '+'); do
        if ! sudo su "$USER" -c groups | grep -Eq " $1|$1 "; then
            sudo gpasswd -a $USER $1
        fi
    done
}

ugroup video
ugroup input

RAW="https://raw.githubusercontent.com"

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
            sed -i "s~$1=.*~$1=$2~g" /etc/environment
        fi
    else
        echo "$1=$2" >>/etc/environment
    fi
}

addenv -f "QT_QPA_PLATFORMTHEME" "qt5ct"
addenv -f "PAGER" "less"
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

if [ -e /etc/lightdm/lightdm.conf ] && ! grep -q 'instantwm' /etc/lightdm/lightdm.conf; then
    sudo sed -i 's/^user-session=.*/user-session=instantwm/g' /etc/lightdm/lightdm.conf
    sudo sed -i '# user-session = Session to load for users/user-session=instantwm/g' /etc/lightdm/lightdm.conf
fi

rm -rf /tmp/instantinstall
mkdir /tmp/instantinstall
cd /tmp/instantinstall

echo "the theme is $THEME"

cd /tmp
rm -rf instantos

# check if computer is a potato
if grep -iq 'Ryzen' /proc/cpuinfo || lshw -C display | grep -q 'nvidia'; then
    echo "classifying pc as not a potato"
else
    echo "looks like your pc is a potato"
    mkdir -p /opt/instantos
    echo "true" >/opt/instantos/potato
fi

# install a custom repo
if ! grep -q '\[instant\]' /etc/pacman.conf; then
    echo "instantos repo not found"

    echo '# paperbegin' >>/etc/pacman.conf
    echo '[instant]' >>/etc/pacman.conf
    echo 'SigLevel = Optional TrustAll' >>/etc/pacman.conf
    echo 'Server = http://instantos.surge.sh' >>/etc/pacman.conf
    echo '# paperend' >>/etc/pacman.conf

else
    echo "instantOS repo found"
fi
