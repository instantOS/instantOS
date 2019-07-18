#!/bin/bash

# Date format, for use as the prompt.
date=$(date +"%a %d. %b %R")

# dmenu cannot display more than 30 lines, to avoid screen clutter. Only relevant if you have more than 30 windows open.
height=$(wmctrl -l | wc -l)
if [[ $height -gt 30 ]]
	then heightfit=30
	else heightfit=$height
fi

num=$(wmctrl -l | sed 's/  / /' | cut -d " " -f 4- | nl -w 3 -n rn | sed -r 's/^([ 0-9]+)[ \t]*(.*)$/\1 - \2/' | dmenu -b -i -p "$date" -l $heightfit | cut -d '-' -f -1)
[[ -z "$num" ]] && exit
wmctrl -l | sed -n "$num p" | cut -c -10 | xargs wmctrl -i -a
