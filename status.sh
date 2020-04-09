#!/bin/bash

##################################
## status monitor for instantWM ##
##################################

INTERNET="X"
date=""

RED='#fc4138'
GREEN='#73d216'

istat() {
    echo "$2" >/tmp/instantos/status/"$1"
}

addstatus() {
    date="${date} [$@]"
}

mkdir -p /tmp/instantos/status

# update different parts with different frequency

# 1m loop
while :; do
    if ping -q -c 1 -W 1 8.8.8.8; then
        INTERNET="^c$GREEN^i^d^"
    else
        INTERNET="^c$RED^X^d^"
    fi
    istat INTERNET "$INTERNET"

    # battery indicator on laptop
    if [ -n "$ISLAPTOP" ]; then
        TMPBAT=$(acpi)
        if [[ $TMPBAT =~ "Charging" ]]; then
            BATTERY="^c$GREEN^"$(egrep -o '[0-9]*%' <<<"$TMPBAT")"^d^"
        else
            BATTERY=$(egrep -o '[0-9]*%' <<<"$TMPBAT")
            # make indicator red on low battery
            if [ $(grep '[0-9]*' <<<"$BATTERY") -lt 10 ]; then
                BATTERY="^c$RED^$BATTERY^d^"
            fi
        fi
        istat BATTERY "B$BATTERY"
    fi
    sleep 1m

    # needed only for shorttime cache, remove in case it changes
    [ -e /tmp/instantos/pasink ] && rm /tmp/instantos/pasink
done &

# 30m loop
while :; do
    sleep 30m
    # check for pacman updates
    if [ "$INTERNET" = "i" ]; then
        if UPDATES=$(checkupdates); then
            echo "$UPDATES updates found"
            UPDATES=$(wc -l <<<"$UPDATES")
        else
            echo "system is up to date"
            unset UPDATES
        fi
        istat UPDATES "U$UPDATES"
    fi
done &

sleep 2

# 10 sec loop
while :; do
    # option to disable status text and check for enabling it again
    if [ -e ~/.instantsilent ]; then
        sleep 1m
        continue
    fi

    for i in /tmp/instantos/status/*; do
        date="${date} [$(cat $i)]"
    done

    # date time
    addstatus "$(date +'%d-%m|%H:%M')"
    # volume
    addstatus "A$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)"

    # add 11 px spacing
    xsetroot -name "^f11^$date"
    date=""

    sleep 10
done
