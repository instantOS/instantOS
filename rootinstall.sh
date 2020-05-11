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
            sudo gpasswd -a "$USER" "$1"
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
addenv -f "EDITOR" "$(which nvim)"

# needed for instantLOCK
if grep -q 'nobody' </etc/groups &>/dev/null || grep -q 'nobody' </etc/group &>/dev/null; then
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

# color scheme for tty
if ! grep -q '# nord colors' /etc/profile; then
    echo "applying color scheme"

    echo '# nord colors' >>/etc/profile
    echo 'if [ "$TERM" = "linux" ]; then' >>/etc/profile

    cat <<EOT >>/etc/profile
    echo -en "\e]P0383c4a" #black
    echo -en "\e]P8404552" #darkgrey
    echo -en "\e]P19A4138" #darkred
    echo -en "\e]P9E7766B" #red
    echo -en "\e]P24BEC90" #darkgreen
    echo -en "\e]PA3CBF75" #green
    echo -en "\e]P3CFCD63" #brown
    echo -en "\e]PBFFD75F" #yellow
    echo -en "\e]P45294e2" #darkblue
    echo -en "\e]PC579CEF" #blue
    echo -en "\e]P5CE50DD" #darkmagenta
    echo -en "\e]PDE7766B" #magenta
    echo -en "\e]P66BE5E7" #darkcyan
    echo -en "\e]PE90FDFF" #cyan
    echo -en "\e]P7CCCCCC" #lightgrey
    echo -en "\e]PFFFFFFF" #white
    clear #for background artifacting
fi

EOT

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
MEMAMOUNT="$(free -m | grep -vi swap | grep -o '[0-9]*' | sort -n | tail -1)"

# computer is not a potato if it has an nvidia card, a ryzen processor or more than 3,5gb of ram.
# it can be unpotatoed at any time.

if grep -iq 'Ryzen' /proc/cpuinfo || lshw -C display | grep -q 'nvidia' || [ "$MEMAMOUNT" -gt 3500 ]; then
    echo "classifying pc as not a potato"
else
    echo "looks like your pc is a potato"
    mkdir -p /opt/instantos
    echo "true" >/opt/instantos/potato
fi

# install a custom repo
if ! grep -q '\[instant\]' /etc/pacman.conf; then
    /usr/share/instantutils/repo.sh
else
    echo "instantOS repo found"
fi

# fix brightness permissions
bash /opt/instantos/menus/data/backlight.sh
