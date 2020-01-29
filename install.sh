#!/bin/bash
# central installer script for instantOS

export PAPERSILENT="True"

if [ $(whoami) = "root" ] || [ $(whoami) = "manjaro" ]; then
    echo "user check successful"
else
    echo "please run this as root"
    exit 1
fi

RAW="https://raw.githubusercontent.com"

if cat /etc/os-release | grep -Eiq 'name.*(arch|manjaro)'; then
    curl -s "$RAW/instantOS/instantLOGO/master/ascii.txt"
    echo ""
else
    echo "distro not supported"
    echo "supported are: Arch, Manjaro"
    exit
fi

REALUSERS="$(ls /home/ | grep -v '+')"
export THEME=${1:-dracula}

# run a tool as every existing
# "real"(there's a human behind it) user

userrun() {
    rm -rf /tmp/instantinstall.sh &>/dev/null
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

rootrun() {
    if [[ "$1" =~ "/" ]]; then
        RUNSCRIPT="$1"
    else
        RUNSCRIPT="$RAW/instantos/instantos/master/$1"
    fi
    shift
    curl -s "$RUNSCRIPT" | bash -s $@
}

echo "installing dependencies"
rootrun depend.sh

echo "root: installing tools"
rootrun rootinstall.sh "$1"

userrun "$RAW/instantos/instantos/master/userinstall.sh"

echo "installing theme"
userrun "$RAW/instantOS/instantTHEMES/master/$THEME.sh"

echo "installing dotfiles"
rootrun $RAW/paperbenni/dotfiles/master/rootinstall.sh
userrun $RAW/paperbenni/dotfiles/master/userinstall.sh

userrun "$RAW/instantos/instantos/master/userdepend.sh"
