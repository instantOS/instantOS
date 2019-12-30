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

if command -v dunst &>/dev/null; then
	mkdir -p /tmp/notifications &>/dev/null
	if ! pgrep dunst; then
		while :; do
			dunst -print |
				cat -v >/tmp/notifications/notif.txt
			sleep 30
		done &
	fi
fi

[ -e /home/benjamin/paperbenni/monitor.sh ] &&
	bash /home/benjamin/paperbenni/monitor.sh &

# chrome os wallpaper changer
[ -e /home/benjamin/paperbenni/menus/dm/wg.sh ] &&
	bash /home/benjamin/paperbenni/menus/dm/wg.sh &

# apply german keybpard layout
if locale | grep -q 'de_DE'; then
	setxkbmap -layout de
fi

# laptop specific background jobs
if [ -n "$ISLAPTOP" ]; then
	command -v libinput-gestures \
		&>/dev/null &&
		libinput-gestures &
	nm-applet &
fi

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
		REPETITIONS="x"
		if ping -q -c 1 -W 1 8.8.8.8; then
			INTERNET="i"
		else
			INTERNET="^c#ff0000^X^d^"
		fi

		# battery indicator on laptop
		if [ -n "$ISLAPTOP" ]; then
			TMPBAT=$(acpi)
			if [[ $TMPBAT =~ "Charging" ]]; then
				BATTERY="^c#00ff00^B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")"^d^"
			else
				BATTERY="B"$(egrep -o '[0-9]*%' <<<"$TMPBAT")
				# make indicator red on low battery
				if [ $(grep '[0-9]*' <<<$BATTERY) -lt 10 ]; then
					BATTERY="^c#ff0000^$BATTERY^d^"
				fi
			fi
		fi

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
