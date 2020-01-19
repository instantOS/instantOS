#!/bin/bash

if [ $(whoami) = "root" ] || [ $(whoami) = "manjaro" ]; then
    echo "user check successful"
else
    echo "please run this as root"
    exit 1
fi

command -v xrandr &>/dev/null ||
    (echo "please install xrandr" && exit 1)

cd

mkdir -p /opt/instantos/monitor &>/dev/null
cd /opt/instantos/monitor

xrandr | grep '[^s]connected' | grep -o '[0-9]*x[0-9]*+[0-9]*' | grep -o '[0-9]*$' >positions.txt
AMOUNT=$(cat positions.txt | wc -l)

# get monitor with highest resolution
xrandr | grep '[^s]connected' | grep -Eo '[0-9]{1,}x[0-9]{1,}\+[0-9]{1,}\+[0-9]{1,}' |
    grep -o '[0-9]*x[0-9]*' >resolutions.txt

if [ $(cat resolutions.txt | sort -u | wc -l) = "1" ]; then
    echo "resolutions identical"
    head -1 resolutions.txt >max.txt
else
    let PIXELS1="$(head -1 resolutions.txt | grep -o '^[0-9]*') * $(cat resolutions.txt | head -1 | grep -o '[0-9]*$')"
    let PIXELS2="$(tail -1 resolutions.txt | grep -o '^[0-9]*') * $(cat resolutions.txt | head -1 | grep -o '[0-9]*$')"
    if [ "$PIXELS1" -gt "$PIXELS2" ]; then
        head -1 resolutions.txt >max.txt
    else
        tail -1 resolutions.txt >max.txt
    fi
fi

if [ "$AMOUNT" = "1" ]; then
    echo "only one monitor found, further setup not needed"
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
