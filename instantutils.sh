#!/bin/bash

# wrapper script for other installation scripts

USAGE="usage: instantutils install
instantutils root
instantutils user
instantutils repo
instantutils refresh"

if [ -z "$1" ]; then
    echo "$USAGE"
    exit
fi

case "$1" in
install)
    sudo /usr/share/instantutils/install.sh
    ;;
root)
    sudo /usr/share/instantutils/rootinstall.sh
    ;;
default)
    /usr/share/instantutils/setup/defaultapps
    ;;
user)
    /usr/share/instantutils/userinstall.sh
    ;;
esac
