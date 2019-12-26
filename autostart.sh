#!/usr/bin/env bash

####################################################
## script for paperbenni-dwm autostart            ##
####################################################

bashes=$(pgrep bash | wc -l)
if [ "$bashes" -gt 2 ]; then
	echo "already running"
	exit
fi

acpi | grep -q '%' && ISLAPTOP="true"

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

# status bar loop
while :; do
	if [ -e ~/.dwmsilent ]; then
		sleep 1m
		continue
	fi

	# run every 60 seconds
	if [ "$REPETITIONS" = "xxxxxx" ]; then
		if ping -q -c 1 -W 1 8.8.8.8; then
			INTERNET="🌍"
		else
			INTERNET="X"
		fi

		# battery indicator on laptop
		[ -n "$ISLAPTOP" ] && date="$date|⚡$(acpi | egrep -o '[0-9]*%')"

		REPETITIONS="x"
	else
		# increase counter
		REPETITIONS="$REPETITIONS"x
	fi

	date="$(date +'%d-%m-%Y|%T')"
	date="$date|🔊$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)|$INTERNET"
	xsetroot -name "$date"
	sleep 10
done
