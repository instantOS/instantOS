#!/usr/bin/env bash

###############################################
## script for instantOS autostart            ##
###############################################

if [ -z "$1" ]; then
	bashes=$(pgrep bash | wc -l)
	if [ "$bashes" -gt 2 ]; then
		echo "already running"
		exit
	fi
else
	echo "force run"
fi

cd
if ! [ -e instantos ]; then
	instantdotfiles &
	mkdir instantos
fi

# find out if we're on an installation medium
if command -v calamares_polkit &>/dev/null; then
	ISLIVE="True"
	echo "live session detected"
fi

# fix small graphical glitch on status bar startup
xdotool key 'super+2'
sleep 0.1
xdotool key 'super+1'

if acpi | grep -q '%' &>/dev/null; then
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

mkdir -p /tmp/notifications &>/dev/null
if ! pgrep dunst; then
	while :; do
		dunst
		sleep 10
	done &
fi

if [ -z "$ISLIVE" ]; then
	cd ~/instantos
	if ! grep -q '....' ~/instantos/monitor/max.txt; then
		instantmonitor
	fi

	[ -e ~/instantos/monitor.sh ] &&
		bash ~/instantos/monitor.sh &

	if ping google.com -c 2; then
		onlinetrigger
	else
		instantwallpaper offline
		for i in $(seq 10); do
			if ping google.com -c 2; then
				onlinetrigger
				break
			else
				sleep 10
			fi
		done
	fi

	# apply german keybpard layout
	if locale | grep -q 'de_DE'; then
		setxkbmap -layout de
	fi
	command -v conky &>/dev/null && conky &

else
	instantmonitor
	/usr/share/instantthemes/manjaro.sh apply
	xrdb ~/.Xresources
	feh --bg-scale /usr/share/liveutils/wallpaper.png
	installapplet &
	sleep 1
	nm-applet &
	sleep 1
	pa-applet &
fi

# laptop specific background jobs
if [ -n "$ISLAPTOP" ]; then
	command -v libinput-gestures \
		&>/dev/null &&
		libinput-gestures &
	! pgrep nm-applet && nm-applet &
fi

source /usr/bin/instantstatus
