#!/usr/bin/env bash

####################################################
## script for paperbenni-dwm autostart            ##
####################################################

bashes=$(pgrep bash | wc -l)
if [ "$bashes" -gt 2 ]; then
	echo "already running"
	exit
fi

if acpi | grep -q '%'; then
	export ISLAPTOP="true"
	echo "laptop detected"
else
	echo "not a laptop"
fi

if command -v picom &>/dev/null; then
	picom &
else
	compton &
fi

sleep 1

if command -v deadd &>/dev/null; then
	if ! pgrep deadd; then
		while :; do
			deadd
			sleep 30
		done &
	fi
fi

# chrome os wallpaper changer
[ -e /home/benjamin/paperbenni/menus/dm/wg.sh ] &&
	bash /home/benjamin/paperbenni/menus/dm/wg.sh

[ -e /home/benjamin/paperbenni/monitor.sh ] &&
	bash /home/benjamin/paperbenni/monitor.sh

# apply german keybpard layout
setxkbmap -layout de

[ -n "$ISLAPTOP" ] && nm-applet &

INTERNET="X"

REPETITIONS="xxxxxx"

command -v conky &>/dev/null && conky &

date=""

addstatus() {
	date="$date[$@] "
}

# status bar loop
while :; do
	if [ -e ~/.dwmsilent ]; then
		sleep 1m
		continue
	fi

	# run every 60 seconds
	if [ "$REPETITIONS" = "xxxxxx" ]; then
		if ping -q -c 1 -W 1 8.8.8.8; then
			INTERNET="i"
		else
			INTERNET="X"
		fi

		# battery indicator on laptop
		[ -n "$ISLAPTOP" ] && BATTERY="B$(acpi | egrep -o '[0-9]*%')"
		REPETITIONS="x"
	else
		# increase counter
		REPETITIONS="$REPETITIONS"x
	fi

	addstatus "$(date +'%d-%m|%H:%M')"
	addstatus "A$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)"
	[ -n "$ISLAPTOP" ] && addstatus "$BATTERY"
	addstatus "$INTERNET"

	xsetroot -name "$date"
	date=""

	sleep 10
done
