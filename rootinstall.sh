#!/bin/bash

####################################################
## installs all system wide tweaks for instantOS  ##
####################################################

if ! [ "$(whoami)" = "root" ]; then
    echo "please run this as root"
    exit 1
fi

mkdir -p /opt/instantos

export RAW="https://raw.githubusercontent.com"

# color scheme for tty
# TODO: redo with pretty font and maybe catpuccin
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

# tmux doesn't count as console user
if ! [ -e /etc/X11/Xwrapper.config ]; then
    echo "enabling startx"
    echo 'allowed_users=anybody' >/etc/X11/Xwrapper.config
fi

if [ -e /opt/livebuilder ]; then
    echo "live session builder detected"
else

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
