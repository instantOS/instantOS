#!/bin/bash

command -v xrandr &>/dev/null ||
    (echo "please install xrandr" && exit 1)

cd
mkdir -p paperbenni/monitor &>/dev/null
cd paperbenni/monitor

xrandr | grep '[^s]connected' | grep -o '[0-9]*x[0-9]*+[0-9]*' | grep -o '[0-9]*$' >positions.txt
AMOUNT=$(cat positions.txt | wc -l)

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
