#!/bin/bash

####################################################
## installs all system wide tweaks for instantOS  ##
####################################################

if ! [ "$(whoami)" = "root" ]; then
    echo "please run this as root"
    exit 1
fi

mkdir -p /opt/instantos

# add group and add users to group
ugroup() {
    groupadd "$1" &>/dev/null
    for USER in $(ls /home/ | grep -v '+'); do
        if id -u "$USER" &>/dev/null; then
            if ! sudo su "$USER" -c groups | grep -Eq " $1|$1 "; then
                sudo gpasswd -a "$USER" "$1"
            fi
        fi
    done
}

ugroup video
ugroup input

export RAW="https://raw.githubusercontent.com"

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
if which nvim; then
    addenv -f "EDITOR" "$(which nvim)"
fi
addenv -f "XDG_MENU_PREFIX" "gnome-"

# needed for instantLOCK
if ! grep -q 'nobody' /etc/groups &>/dev/null && ! grep -q 'nobody' </etc/group &>/dev/null; then
    echo "created group nobody"
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

    {
        echo '# nord colors'
        echo 'if [ "$TERM" = "linux" ]; then'
    } >>/etc/profile

    cat <<EOT >>/etc/profile
    echo -en "\e]P0 #3F4451" #black
    echo -en "\e]P8 #4F5666" #darkgrey
    echo -en "\e]P1 #E05561" #darkred
    echo -en "\e]P9 #FF616E" #red
    echo -en "\e]P2 #8CC265" #darkgreen
    echo -en "\e]PA #A5E075" #green
    echo -en "\e]P3 #D18F52" #brown
    echo -en "\e]PB #F0A45D" #yellow
    echo -en "\e]P4 #4AA5F0" #darkblue
    echo -en "\e]PC #4DC4FF" #blue
    echo -en "\e]P5 #C162DE" #darkmagenta
    echo -en "\e]PD #DE73FF" #magenta
    echo -en "\e]P6 #42B3C2" #darkcyan
    echo -en "\e]PE #4CD1E0" #cyan
    echo -en "\e]P7 #D7DAE0" #lightgrey
    echo -en "\e]PF #E6E6E6" #white
    clear #for background artifacting
fi

EOT

fi

# /tmp/topinstall is present if rootinstall is running on postinstall
# like on existing installations
if ! [ -e /tmp/topinstall ] && command -v plymouth-set-default-theme && ! grep -iq 'manjaro' /etc/os-release; then
    # install a custom repo
    if ! grep -q '\[instant\]' /etc/pacman.conf; then
        echo "restoring repo"
        /usr/share/instantutils/repo.sh
    else
        echo "instantOS repo found"
    fi

    sed -i 's/DISTRIB_DESCRIPTION.*/DISTRIB_DESCRIPTION="instantOS"/g' /etc/lsb-release

    if ! [ -e /opt/instantos/bootscreen ] && [ -e /opt/instantos/realinstall ] && ! [ -e /opt/instantos/noplymouth ]; then
        echo "installing boot splash screen"
        plymouth-set-default-theme instantos

        if [ -e /etc/default/grub ]; then
            if ! grep -q 'instantos boot animation' /etc/default/grub; then
                # boot animation
                sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT="/aGRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT quiet splash loglevel=3 rd.udev.log_priority=3 vt.global_cursor_default=0" # instantos boot animation' \
                    /etc/default/grub
                # set grub entry name
                sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="instantOS"/g' /etc/default/grub
            fi
        fi

        if ! grep -q '.*plymouth.* # boot screen' /etc/mkinitcpio.conf; then
            sed -i '/^HOOKS/aHOOKS+=(plymouth) # boot screen' /etc/mkinitcpio.conf
        fi

        systemctl disable lightdm
        systemctl enable lightdm-plymouth

        if [ -e /etc/default/grub ]; then
            update-grub
        fi
        mkinitcpio -P
        touch /opt/instantos/bootscreen
    fi
fi

# tmux doesn't count as console user
if ! [ -e /etc/X11/Xwrapper.config ]; then
    echo "enabling startx"
    echo 'allowed_users=anybody' >/etc/X11/Xwrapper.config
fi

if [ -e /opt/livebuilder ]; then
    echo "live session builder detected"
else
    if [ -e /etc/lightdm/lightdm.conf ] && ! grep -q 'instantwm' /etc/lightdm/lightdm.conf; then
        sudo sed -i 's/^user-session=.*/user-session=instantwm/g' /etc/lightdm/lightdm.conf
        sudo sed -i '# user-session = Session to load for users/user-session=instantwm/g' /etc/lightdm/lightdm.conf
    fi

    # check if computer is a potato
    MEMAMOUNT="$($(which free) -m | grep -vi swap | grep -o '[0-9]*' | sort -n | tail -1)"

    # computer is not a potato if it has an nvidia card, a ryzen processor or more than 3,5gb of ram.
    # it can be unpotatoed at any time.

    if grep -iq 'Ryzen' /proc/cpuinfo || lshw -C display | grep -q 'nvidia' || [ "$MEMAMOUNT" -gt 3500 ]; then
        echo "classifying pc as not a potato"
    else
        echo "looks like your pc is a potato"
        mkdir -p /opt/instantos
        echo "true" >/opt/instantos/potato
    fi

    # fix brightness permissions
    bash /usr/share/instantassist/data/backlight.sh
    mkdir -p /opt/instantos
fi

if [ -e /etc/geoclue/geoclue.conf ] && ! grep -q '^\[redshift' /etc/geoclue/geoclue.conf; then
    # make sure redshift can use geoclue
    echo 'applying redshift fix'
    {
        echo ''
        echo '[redshift]'
        echo 'allowed=true'
        echo 'system=false'
        echo 'users='
    } >>/etc/geoclue/geoclue.conf

    # apply api key
    sed -i '0,/^#url=.*mozilla/{s/^#url=.*mozilla.*/url=https:\/\/location.services.mozilla.com\/v1\/geolocate?key=2bc2a500-5d25-4ae2-a484-7a70cb7cb99e/g}' /etc/geoclue/geoclue.conf

fi

# indicator file
touch /opt/instantos/rootinstall
