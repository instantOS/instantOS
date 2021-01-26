#!/bin/bash

# wrapper script for other installation scripts

USAGE="usage:
instantutils root
instantutils user
instantutils repo
instantutils alttab
instantutils refresh"

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
    if [ -z "$2" ]
    then
        echo "usage: instantutils open defaultappname"
        exit
    fi
    if ! [ -e ~/.config/instantos/default/"$2" ]
    then
        instantutils default
        chmod +x ~/.config/instantos/default/"$2"
    fi
    APP="$2"
    shift 2
    ~/.config/instantos/default/"$APP" "$@"
    ;;
esac
