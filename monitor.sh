#!/bin/bash

command -v xrandr &>/dev/null ||
    (echo "please install xrandr" && exit 1)
cd

mkdir -p ~/instantos/monitor &>/dev/null
cd ~/instantos/monitor

xrandr | grep '[^s]connected' | grep -o '[0-9]*x[0-9]*+[0-9]*' | grep -o '[0-9]*$' >positions.txt
AMOUNT=$(wc -l <positions.txt)

# get monitor with highest resolution
RESOLUTIONS=$(xrandr | grep '[^s]connected' | grep -Eo '[0-9]{1,}x[0-9]{1,}\+[0-9]{1,}\+[0-9]{1,}' |
    grep -o '[0-9]*x[0-9]*' | sed 's/ /\n/g')
OLDRES=$(cat resolutions.txt)

# see if resolution has changed
if ! [ "$RESOLUTIONS" = "$OLDRES" ]; then
    echo "$RESOLUTIONS" >resolutions.txt
    sed -i 's/ /\n/g' resolutions.txt
    CHANGERES="True"
    echo "Resolution change detected"
fi

if [ $(sort -u resolutions.txt | wc -l) = "1" ]; then
    echo "resolutions identical"
    head -1 resolutions.txt >max.txt
else
    let PIXELS1="$(head -1 resolutions.txt | grep -o '^[0-9]*') * $(head -1 resolutions.txt | grep -o '[0-9]*$')"
    let PIXELS2="$(tail -1 resolutions.txt | grep -o '^[0-9]*') * $(head -1 resolutions.txt | grep -o '[0-9]*$')"
    if [ "$PIXELS1" -gt "$PIXELS2" ]; then
        head -1 resolutions.txt >max.txt
    else
        tail -1 resolutions.txt >max.txt
    fi
fi

# rebuild wallpaper after resolution change
changetrigger() {
    if [ -z "$CHANGERES" ]; then
        echo "no resolution change"
    else
        if [ -e ~/instantos/wallpapers ] && command -v instantwallpaper; then
            rm -rf ~/instantos/wallpapers
            instantwallpaper random
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

xrandr | grep '[^s]connected' | grep -o '^[^ ]*' >names.txt
MONITOR1=$(head -1 positions.txt)
MONITOR2=$(tail -1 positions.txt)

if [ "$MONITOR1" -gt "$MONITOR2" ]; then
    echo "Monitor 1 is ${MONITOR1}px on the right"
    echo "$MONITOR1" >right.txt
else
    echo "Monitor 2 is ${MONITOR2}px on the right"
    echo "$MONITOR1" >right.txt
fi
changetrigger
