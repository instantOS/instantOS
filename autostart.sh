#!/usr/bin/env bash

####################################################
## script for paperbenni-dwm autostart            ##
####################################################

for i in $(pidof -x autostart.sh); do
	echo "pid $i"
	if [ -z "$AUTOSTARTPID" ]; then
		AUTOSTARTPID="$i"
	else
		echo "other instance of dwm autostart already running"
		exit
	fi
done

[ -e ~/.cache/islaptop ] && ISLAPTOP="true"
INTERNET="X"

REPETITIONS="xxxxxx"

# status bar loop
while :; do
	# run every 60 seconds
	if [ "$REPETITIONS" = "xxxxxx" ]; then
		if ping -q -c 1 -W 1 8.8.8.8; then
			INTERNET="🌍"
		else
			INTERNET="X"
		fi
		REPETITIONS="x"
	else
		REPETITIONS="$REPETITIONS"x
	fi

	date="$(date +'%d-%m-%Y|%T')"

	# battery indicator on laptop
	[ -n "$ISLAPTOP" ] && date="$date|$(acpi | egrep -o '[0-9]*%')"
	date="$date|🔊$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)|$INTERNET"
	xsetroot -name "$date"
	sleep 10
done &

if command -v picom &> /dev/null; then
	picom &
else
	compton &
fi

sleep 1

if ! pgrep deadd; then
	while :; do
		deadd
		sleep 30
	done &
fi

# chrome os wallpaper changer
[ -e /home/benjamin/paperbenni/menus/dm/wg.sh ] &&
	bash /home/benjamin/paperbenni/menus/dm/wg.sh

[ -n "$ISLAPTOP" ] && nm-applet &
