#!/bin/bash

##################################
## status monitor for instantWM ##
##################################

# will be rewritten soon

INTERNET="X"
date=""

ORANGE='#FFC87C'
RED='#F28B82'
DARKERRED='#BF554D'
GREEN='#5D9E70'
LIGHTGREEN='#81C995'
DARKBACK='#3E485A'
LIGHTBACK='#5B6579'
DARKTEXT='#121212'

istat() {
    echo "$2" >/tmp/instantos/status/"$1"
}

mkdir -p /tmp/instantos/status

# update different parts with different frequency

# 1m loop
while :; do
    if ping -q -c 1 -W 1 8.8.8.8; then
        INTERNET="^c$LIGHTGREEN^^t$DARKTEXT^  i  ^d^"
    else
        INTERNET="^c$DARKERRED^^t$DARKTEXT^  i  ^d^"
    fi

    istat INTERNET "$INTERNET"

    # battery indicator on laptop
    if [ -n "$ISLAPTOP" ]; then
        TMPBAT=$(acpi | grep -iv Unknown | head -1)
        if [[ $TMPBAT =~ "Charging" ]]; then
            BATTERY="^c$GREEN^^t$DARKTEXT^  B$(echo "$TMPBAT" | grep -oP '\d+(?=%)')% "
        elif [[ $TMPBAT =~ "Discharging" ]]; then
            BATTERY="^c$ORANGE^^t$DARKTEXT^  B$(echo "$TMPBAT" | grep -oP '\d+(?=%)')% "
            # make indicator red on low battery
            BATTERY_PERCENTAGE=$(echo "$BATTERY" | grep -oP '\d+(?=%)')
        if [ -n "$BATTERY_PERCENTAGE" ] && [ "$BATTERY_PERCENTAGE" -lt 20 ]; then
            BATTERY="^c$RED^^t$DARKTEXT^  B$(echo "$TMPBAT" | grep -oP '\d+(?=%)')% ^d^"
        fi

        else
            BATTERY="  B$(echo "$TMPBAT" | grep -oP '\d+(?=%)')%  "
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
    # TODO make instantthemes only do something if time/variant/theme has changed
    # instantthemes apply
done &

sleep 2

# 10 sec loop
while :; do

    for i in /tmp/instantos/status/*; do
        date="${date}$(cat "$i")"
    done

    if iconf -i 12hclock; then
        clock="$(date +'%l:%M %p')"
        # remove space from the beginning when it's present
        if [ "${clock:0:1}" = " " ]; then
            clock="${clock:1}"
        fi
    else
        clock="$(date +'%H:%M')"
    fi

    # date time
    date="$date^d^  $(date +'%d-%m')  ^c$DARKBACK^  $clock  "
    # volume
    date="$date^c$LIGHTBACK^  A$(/usr/share/instantassist/utils/p.sh g)%  "

    # option to disable status text
    if [ -e ~/.instantsilent ] && [ -z "$FORCESTATUS" ]; then
        echo "^d^^f11^$date^d^"
    else
        # add 11 px spacing
        xsetroot -name "^d^^f11^$date^d^"
    fi

    date=""
    sleep 10
done
