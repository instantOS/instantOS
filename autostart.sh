#!/bin/bash

####################################################
## script for paperbenni-dwm autostart            ##
####################################################

AUTOSTARTID="$(pgrep autostart.sh)"
n="${AUTOSTARTID//[^\n]/}"
if [ ${#n} -eq 1 ]; then
	echo "No running instances found"
else
	echo "another instance already running, exiting"
	exit
fi

if command -v mpv && [ -e ~/paperbenni/boot.wav ]; then
	mpv ~/paperbenni/boot.wav &
fi &

if ! [ -e ~/.dwmrunning ]; then
	while :; do
		date="$(date)"
		ping -q -c 1 -W 1 8.8.8.8 && date="$date|""🌍"
		date="$date|🔊$(amixer get Master | egrep -o '[0-9]{1,3}%' | head -1)"
		xsetroot -name "$date"
		sleep 1m

	done &
	compton &
fi

touch ~/.dwmrunning

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

if [ -e ~/paperbenni/wallpaper.sh ]; then
	bash ~/paperbenni/wallpaper.sh
fi
