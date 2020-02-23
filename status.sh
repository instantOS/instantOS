#!/bin/bash

INTERNET="X"
REPETITIONS="xxxxxx"
date=""

addstatus() {
    date="$date[$@] "
}

# status bar loop
while :; do
    if [ -e ~/.instantsilent ]; then
        sleep 1m
        continue
    fi

    # run every 60 seconds
    if [ "$REPETITIONS" = "xxxxxx" ]; then
        REPETITIONS="x"
        if ping -q -c 1 -W 1 8.8.8.8; then
            INTERNET="i"
        else
            INTERNET="^c#ff0000^X^d^"
        fi

        # battery indicator on laptop
        if [ -n "$ISLAPTOP" ]; then
            TMPBAT=$(acpi)
            if [[ $TMPBAT =~ "Charging" ]]; then
                BATTERY="^c#00ff00^B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")"^d^"
            else
                BATTERY="B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")
                # make indicator red on low battery
                if [ $(grep '[0-9]*' <<<$BATTERY) -lt 10 ]; then
                    BATTERY="^c#ff0000^$BATTERY^d^"
                fi
            fi
        fi

    else
        # increase counter
        REPETITIONS="$REPETITIONS"x
    fi

    addstatus "$(date +'%d-%m|%H:%M')"
    addstatus "A$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)"
    [ -n "$ISLAPTOP" ] && addstatus "$BATTERY"
    addstatus "$INTERNET"

    xsetroot -name "^f11^$date"
    date=""

    sleep 10
done
