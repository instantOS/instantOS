#!/bin/bash

# wrapper script for other installation scripts

USAGE="usage: instantutils [action]
    root              execute postinstall steps for root owned files
    root              execute postinstall steps for user owned files
    repo              add instantOS repos to the system
    alttab            launch alttab with instantOS theming
    default           create symlinks for default applications
    open              open default application \$2
    conky             launch conky with instantOS tooltips
    rangerplugins     install instantOS ranger plugins
    help              show this message"

if [ -z "$1" ]; then
    echo "$USAGE"
    exit
fi

case "$1" in
root)
    sudo /usr/share/instantutils/rootinstall.sh
    ;;
default)
    /usr/share/instantutils/setup/defaultapps
    ;;
alttab)
    alttab -fg "#ffffff" -bg "#292F3A" -frame "#5293E1" -d 0 -s 1 -t 128x150 -i 127x64 -w 1 -vp pointer &
    ;;
user)
    /usr/share/instantutils/userinstall.sh
    ;;
repo)
    /usr/share/instantutils/repo.sh
    ;;
open)
    if [ -z "$2" ]; then
        echo "usage: instantutils open defaultappname"
        exit
    fi
    if ! [ -e ~/.config/instantos/default/"$2" ]; then
        instantutils default
        chmod +x ~/.config/instantos/default/"$2"
    fi
    APP="$2"
    shift 2
    ~/.config/instantos/default/"$APP" "$@"
    ;;
rangerplugins)
    cd || exit 1
    mkdir instantos &>/dev/null
    echo "installing ranger plugins"
    mkdir -p ~/.config/ranger/plugins
    cp -r /usr/share/rangerplugins/* ~/.config/ranger/plugins/
    ;;
conky)
    shuf /usr/share/instantwidgets/tooltips.txt | head -1 >~/.cache/tooltip
    conky -c /usr/share/instantwidgets/tooltips.conf &
    ;;
*)
    echo "$USAGE"
    ;;
esac
