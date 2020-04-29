#!/bin/bash

command -v xrandr &>/dev/null ||
    (echo "please install xrandr" && exit 1)
cd

mkdir -p ~/instantos/monitor &>/dev/null
cd ~/instantos/monitor

POSITIONS="$(xrandr | grep '[^s]connected' | grep -o '[0-9]*x[0-9]*+[0-9]*' | grep -o '[0-9]*$')"
AMOUNT=$(wc -l <<<"$POSITIONS")

# get monitor with highest resolution
RESOLUTIONS=$(xrandr | grep '[^s]connected' | grep -Eo '[0-9]{1,}x[0-9]{1,}\+[0-9]{1,}\+[0-9]{1,}' |
    grep -o '[0-9]*x[0-9]*' | sed 's/ /\n/g')

if OLDRES="$(iconf resolutions)"; then
    # see if resolution has changed
    if ! [ "$RESOLUTIONS" = "$OLDRES" ]; then
        iconf resolutions "$RESOLUTIONS"
        CHANGERES="True"
        echo "Resolution change detected"
    fi
fi

if [ $(echo "$RESOLUTIONS" | sort -u | wc -l) = "1" ]; then
    echo "resolutions identical"
    iconf -i max $(head -1 <<<"$RESOLUTIONS")
else
    let PIXELS1="$(head -1 <<<$RESOLUTIONS | grep -o '^[0-9]*') * $(head -1 <<<$RESOLUTIONS | grep -o '[0-9]*$')"
    let PIXELS2="$(tail -1 <<<$RESOLUTIONS | grep -o '^[0-9]*') * $(tail -1 <<<$RESOLUTIONS | grep -o '[0-9]*$')"
    if [ "$PIXELS1" -gt "$PIXELS2" ]; then
        iconf -i max "$(head -1 <<<$RESOLUTIONS)"
    else
        iconf -i max "$(tail -1 <<<$RESOLUTIONS)"
    fi
fi

# rebuild wallpaper after resolution change
changetrigger() {
    if [ -z "$CHANGERES" ]; then
        echo "no resolution change"
    else
        if [ -e ~/instantos/wallpapers ] && command -v instantwallpaper; then
            rm -rf ~/instantos/wallpapers
            instantwallpaper w
        fi
    fi
}

if [ "$AMOUNT" = "1" ]; then
    echo "only one monitor found, further setup not needed"
    changetrigger
    exit
else
    if [ "$AMOUNT" -gt 2 ]; then
        echo "only 2 monitors are supported"
        exit
    fi
    echo "$AMOUNT monitors found"
fi

iconf names "$(xrandr | grep '[^s]connected' | grep -o '^[^ ]*')"

MONITOR1=$(head -1 <<<"$POSITIONS")
MONITOR2=$(tail -1 <<<"$POSITIONS")

if [ "$MONITOR1" -gt "$MONITOR2" ]; then
    echo "Monitor 1 is ${MONITOR1}px on the right"
    iconf -i right "$MONITOR2"
else
    echo "Monitor 2 is ${MONITOR2}px on the right"
    iconf -i right "$MONITOR2"
fi
changetrigger
