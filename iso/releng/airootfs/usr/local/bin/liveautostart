#!/bin/bash

# this script autostarts on an instantOS live session

echo "applying live session tweaks"
# increase tmpfs size depending on ram size
MEMSIZERAW="$(grep MemTotal /proc/meminfo | grep -o '[0-9]*' | head -1)"

if command -v systemctl; then
    sudo systemctl enable --now systemd-timesyncd
    # auto detect time zone
    if command -v tzupdate; then
        sleep 10
        sudo tzupdate
    fi &
fi

if grep -Eq '.{7,}'; then
    GIGSIZE="$(sed 's/......$//g' <<<"$MEMSIZERAW")"
    echo "$GIGSIZE gigs of ram detected"
    if [ "$GIGSIZE" -gt 1 ]; then
        TMPSIZE="$((GIGSIZE / 2))"
    fi
    if [ "$TMPSIZE" -eq "$TMPSIZE" ] && [ "$TMPSIZE" -gt 0 ]; then
        echo "numbers look fine"
    else
        echo "failed setting tmpfs size"
        exit
    fi
    echo "setting tmpfs size to $TMPSIZE"
    mount -o remount,size="${TMPSIZE}G" /run/archiso/cowspace

else
    echo "defaulting to 512Mb of cowspace"
    mount -o remount,size=512M /run/archiso/cowspace
fi

echo "finished applying live session tweaks"
