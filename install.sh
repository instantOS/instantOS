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

if ! grep -Eiq 'name.*(arch|manjaro)' /etc/os-release; then
    curl -s "$RAW/instantOS/instantLOGO/master/ascii.txt"
    echo "warning: distro unsupported"
fi

REALUSERS="$(ls /home/ | grep -v '+')"
export THEME=${1:-arc}

# run a tool as every existing
# "real"(there's a human behind it) user

userrun() {
    for i in $REALUSERS; do
        echo "processing user $i"
        sudo su "$i" -c "$1"
    done
}

echo "installing dependencies"
/usr/share/instantutils/depend.sh

echo "root: installing tools"
/usr/share/instantutils/rootinstall.sh
/usr/share/instantdotfiles/rootinstall.sh

userrun /usr/share/instantutils/userinstall.sh

instantthemes f

echo "installing dotfiles"
instantdotfiles -f root
