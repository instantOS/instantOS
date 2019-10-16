#!/bin/bash
while :; do
	date="$(date)"
	ping -q -c 1 -W 1 8.8.8.8 && date="$date|""🌍"
	date="$date|🔊$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)"
	xsetroot -name "$date"
	sleep 1m
done &

feh --bg-scale ~/wallpapers/wallpaper.jpg

if command -v deadd-notification-center; then
	deadd-notification-center &
fi

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

if ! pgrep deadd-notification-center; then
	while :; do
		deadd-notification-center
		sleep 1
	done
fi
