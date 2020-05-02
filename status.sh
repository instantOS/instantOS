#!/bin/bash

##################################
## status monitor for instantWM ##
##################################

INTERNET="X"
date=""

RED='#fc4138'
GREEN='#52E067'
DARKBACK='#3E485A'
LIGHTBACK='#5B6579'

istat() {
    echo "$2" >/tmp/instantos/status/"$1"
}

mkdir -p /tmp/instantos/status

# update different parts with different frequency

# 1m loop
while :; do
    if ping -q -c 1 -W 1 8.8.8.8; then
        INTERNET="^c$GREEN^  i  ^d^"
    else
        INTERNET="^c$RED^  i  ^d^"
    fi

    istat INTERNET "$INTERNET"

    # battery indicator on laptop
    if [ -n "$ISLAPTOP" ]; then
        TMPBAT=$(acpi)
        if [[ $TMPBAT =~ "Charging" ]]; then
            BATTERY="^c$GREEN^  B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")"  "
        else
            BATTERY="  B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")"  "
            # make indicator red on low battery
            if [ $(grep '[0-9]*' <<<"$BATTERY") -lt 10 ]; then
                BATTERY="^c$RED^  B$BATTERY  ^d^"
            fi
        fi
        istat BATTERY "$BATTERY"
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

    if ! iconf -i notheming; then
        DATEHOUR="$(date +%H)"
        if [ "$DATEHOUR" -lt "7" ] || [ "$DATEHOUR" -gt "20" ]; then
            if ! [ -e /tmp/instantdarkmode ]; then
                instantthemes d &
                touch /tmp/instantdarkmode
                [ -e /tmp/instantlightmode ] && rm /tmp/instantlightmode
            fi
        else
            if ! [ -e /tmp/instantlightmode ]; then
                instantthemes l &
                touch /tmp/instantlightmode
                [ -e /tmp/instantdarkmode ] && rm /tmp/instantdarkmode

            fi
        fi
    fi

done &

sleep 2

# 10 sec loop
while :; do
    # option to disable status text and check for enabling it again
    if [ -e ~/.instantsilent ] && [ -z "$FORCESTATUS" ]; then
        sleep 1m
        continue
    fi

    for i in /tmp/instantos/status/*; do
        date="${date}$(cat $i)"
    done

    # date time
    date="$date^d^  $(date +'%d-%m')  ^c$DARKBACK^  $(date +'%H:%M')  "
    # volume
    date="$date^c$LIGHTBACK^  A$(amixer get Master | grep -Eo '[0-9]{1,3}%' | head -1)  "

    # add 11 px spacing
    xsetroot -name "^d^^f11^$date^d^"
    date=""

    sleep 10
done
