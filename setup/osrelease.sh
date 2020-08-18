#!/bin/bash

if ! whoami | grep -q '^root$'; then
    echo "please run this as root"
    exit
fi

CHANGEFILE=/etc/os-release

setoption() {
    if grep -q "^$1" "$CHANGEFILE"; then
        sed -i "/^$1/d'" "$CHANGEFILE"
    fi
    echo "$1=\"$2\""
}

setoption ID_LIKE arch
setoption NAME instantos
setoption PRETTY_NAME instantOS
setoption HOME_URL "https://instantos.io/"
setoption LOGO instantos

CHANGEFILE=/etc/lsb-release

setoption DISTRIB_DESCRIPTION instantOS
