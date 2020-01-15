#!/bin/bash
# central installer script for pb suckless

if [ $(whoami) = "root" ] || [ $(whoami) = "manjaro" ]; then
    echo "user check successful"
else
    echo "please run this as root"
    exit 1
fi

RAW="https://raw.githubusercontent.com"

if cat /etc/os-release | grep -Eiq 'name.*(arch|manjaro|ubuntu)'; then
    curl -s "$RAW/instantOS/instantLOGO/master/ascii.txt"
else
    echo "distro not supported"
    echo "supported are: Arch, Manjaro, Ubuntu"
    exit
fi

REALUSERS="$(ls /home/ | grep -v '+')"
export THEME=${1:-dracula}

# run a tool as every existing
# "real"(there's a human behind it) user

userrun() {
    rm -rf /tmp/instantinstall.sh &> /dev/null
    curl -s "$1" >/tmp/instantinstall.sh
    chmod 777 /tmp/instantinstall.sh

    if [ -n "$2" ] && getent passwd $2 && [ -e /home/$2 ]; then
        echo "single user installation for $1"
        sudo su "$2" -c /tmp/instantinstall.sh
    else
        for i in $REALUSERS; do
            echo "processing user $i"
            sudo su "$i" -c /tmp/instantinstall.sh
        done
    fi
    rm /tmp/instantinstall.sh
}

echo "installing dependencies"
curl -s $RAW/paperbenni/suckless/master/depend.sh | bash

echo "installing tools"
curl -s $RAW/paperbenni/suckless/master/rootinstall.sh | bash
userrun "$RAW/paperbenni/suckless/master/userinstall.sh"

echo "installing theme"
userrun "$RAW/instantOS/instantTHEMES/master/$THEME.sh"

echo "installing dotfiles"
curl -s $RAW/paperbenni/dotfiles/master/rootinstall.sh | bash
userrun $RAW/paperbenni/dotfiles/master/install.sh
