#!/bin/bash

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

while :; do
	if ping -q -c 1 -W 1 8.8.8.8; then
		INTERNET="🌍"
	else
		INTERNET="X"
	fi
	sleep 1m
done &

# status bar loop
while :; do
	date="$(date +'%d-%m-%Y|%T')"
	# battery indicator on laptop
	[ -n ISLAPTOP ] && date="$date|$(acpi | egrep -o '[0-9]*%')"
	date="$date|🔊$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)|$INTERNET"
	xsetroot -name "$date"
	sleep 10
done &
compton &

if ! pgrep mate-settings; then
	while :; do
		if command -v mate-settings-daemon; then
			mate-settings-daemon
		else
			/usr/lib/mate-settings-daemon/mate-settings-daemon
		fi
		sleep 1
	done &
fi

sleep 1

if ! pgrep deadd; then
	while :; do
		deadd
		sleep 1
	done &
fi

# chrome os wallpaper changer
[ -e /home/benjamin/paperbenni/menus/dm/wg.sh ] &&
	bash /home/benjamin/paperbenni/menus/dm/wg.sh

[ -n "$ISLAPTOP" ] && nm-applet &
