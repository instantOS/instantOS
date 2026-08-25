#!/bin/bash

##################################
## status monitor for instantWM ##
##################################

# will be rewritten soon

INTERNET="X"
date=""

RED='#F28B82'
GREEN='#81C995'
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
        INTERNET="^c$GREEN^^t$DARKTEXT^  i  ^d^"
    else
        INTERNET="^c$RED^^t$DARKTEXT^  i  ^d^"
    fi

    istat INTERNET "$INTERNET"

    # battery indicator on laptop
    if [ -n "$ISLAPTOP" ]; then
        TMPBAT=$(acpi | grep -iv Unknown | head -1)
        BATTERY_PERCENTAGE="$(grep -Eo '[0-9]+%' <<<"$TMPBAT")"
        if [[ $TMPBAT =~ "Charging" ]]; then
            BATTERY="^c$GREEN^^t$DARKTEXT^  B${BATTERY_PERCENTAGE}  "
        else
            BATTERY="  B${BATTERY_PERCENTAGE}  "
            # make indicator red on low battery
            if [ "${BATTERY_PERCENTAGE%%%}" -lt 10 ]; then
                BATTERY="^c$RED^^t$DARKTEXT^  B$BATTERY  ^d^"
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
    cur_vol=""
    if command -v wpctl >/dev/null 2>&1; then
        cur_vol="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2 * 100)}')"
    elif command -v pamixer >/dev/null 2>&1; then
        cur_vol="$(pamixer --get-volume 2>/dev/null)"
    elif command -v pactl >/dev/null 2>&1; then
        cur_vol="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{print $5}' | tr -d '%' | head -n 1)"
    fi
    [ -z "$cur_vol" ] && cur_vol="0"
    date="$date^c$LIGHTBACK^  A${cur_vol}%  "

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
