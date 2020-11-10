#!/bin/bash

# simple way to remember most frequently used items out of a cache

ICACHE="$HOME/.cache/instantos/smart/$1"
if [ -n "$3" ]; then
    # add entry
    if [ -e ~/.cache/instantos/smart/"$1" ]; then
        if [ "$(wc -l <"$ICACHE")" -gt "$3" ]; then
            # make cache conform to max size
            sed -i "1,${4:-50}d" "$ICACHE"
        fi
    else
        mkdir -p ~/.cache/instantos/smart
    fi
    echo "$2" >>"$ICACHE"
elif [ -z "$1" ]; then
    echo "usage:
smartcat cachename
or
smartcat cachename addedentry maxnumber clearamount" 1>&2
    exit 1
else
    # get contents
    tac "$ICACHE" | perl -nE '$seen{$_}++ or print'
fi
