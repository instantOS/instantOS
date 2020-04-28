#!/usr/bin/env bash

###############################################
## script for instantOS autostart            ##
###############################################

if [ -z "$1" ]; then
	if uname -m | grep -q '^arm'; then
		if [ -e /tmp/osautostart ]; then
			echo "already running"
			exit
		else
			touch /tmp/osautostart
			export ISRASPI=true
		fi
	else
		bashes=$(pgrep bash | wc -l)
		if [ "$bashes" -gt 2 ]; then
			echo "already running"
			exit
		fi
	fi
else
	echo "forced run"
fi

cd
if ! iconf -i dotfiles; then
	echo "installing dotfiles"
	instantdotfiles &
	mkdir instantos
	iconf -i dotfiles 1

	echo "installing ranger plugins"
	mkdir -p ~/.config/ranger/plugins
	cp -r /usr/share/rangerplugins/* ~/.config/ranger/plugins/

fi

# find out if we're on an installation medium
if command -v calamares_polkit &>/dev/null; then
	ISLIVE="True"
	echo "live session detected"
fi

# fix small graphical glitch on status bar startup
NMON=$(iconf names | wc -l)
for i in $(eval "echo {1..$NMON}"); do
	xdotool key 'super+2' && sleep 0.1
	xdotool key 'super+0' && sleep 0.1
	xdotool key 'super+c' && sleep 0.1
	xdotool key 'super+1' && sleep 0.1
	xdotool key 'super+comma' && sleep 0.1
done &

if [ -n "$ISRASPI" ]; then
	# enable double drawing for moving floating windows
	# greatly increases smoothness
	xdotool key super+alt+shift+d
	if ! [ -e ~/.config/instantos/israspi ]; then
		echo "marking machine as raspi"
		mkdir -p ~/.config/instantos
		touch ~/.config/instantos/israspi
		# logo does not work on raspi
		iconf -i nologo 1
	fi
fi

if iconf islaptop; then
	export ISLAPTOP="true"
	echo "laptop detected"
else
	echo "not a laptop"
fi

if ! [ -e /opt/instantos/potato ]; then
	picom &
else
	echo "your computer is a potato"
fi

if ! iconf -i instantthemes; then
	instantthemes a
	xrdb ~/.Xresources
	iconf -i instantthemes 1
fi

# dynamically switch between light and dark gtk theme
DATEHOUR=$(date +%H)
if [ "$DATEHOUR" -gt "20" ]; then
	instantthemes d &
else
	instantthemes l &
fi &

mkdir -p /tmp/notifications &>/dev/null
if ! pgrep dunst; then
	while :; do
		dunst
		sleep 10
	done &
fi

onlinetrigger() {
	instantwallpaper &
}

# set up oh-my-zsh config if not existing already
instantshell &

if [ -z "$ISLIVE" ]; then
	cd ~/instantos
	if ! iconf -i max; then
		instantmonitor
	fi

	if [ -e ~/instantos/monitor.sh ]; then
		bash ~/instantos/monitor.sh &
	elif [ -e ~/.config/autorandr/instantos/config ]; then
		autorandr instantos &
	fi

	if ping google.com -c 2; then
		onlinetrigger
	else
		# fall back to already installed wallpapers
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

	# apply keybpard layout
	if [ -e ~/instantos/keyboard ]; then
		setxkbmap -layout $(cat ~/instantos/keyboard)
	else
		CURLOCALE=$(locale | grep LANG | sed 's/.*=\(.*\)\..*/\1/')
		case "$CURLOCALE" in
		de_DE)
			setxkbmap -layout de

			;;
		*)
			echo "no keyboard layout found for your locale"
			;;
		esac
	fi

	shuf /usr/share/instantwidgets/tooltips.txt | head -1 >~/.cache/tooltip
	conky -c /usr/share/instantwidgets/tooltips.conf &

	# don't need applet for ethernet
	if [ -e ~/.cache/haswifi ]; then
		echo "wifi enabled"
		while :; do
			if ! pgrep nm-applet; then
				nm-applet &
			fi
			sleep 6m
		done &
	fi

else
	instantmonitor
	feh --bg-scale /usr/share/instantwallpaper/defaultphoto.png
	conky -c /usr/share/instantwidgets/install.conf &
	sleep 0.3
	while :; do
		if ! pgrep nm-applet; then
			installapplet &
			nm-applet &
		fi
		sleep 6m
	done &
	sleep 1
fi

# laptop specific background jobs
if [ -n "$ISLAPTOP" ]; then
	echo "libinput gestures"
	command -v libinput-gestures \
		&>/dev/null &&
		libinput-gestures &
fi

source /usr/bin/instantstatus &
lxpolkit &
xfce4-power-manager &

# welcome greeter app
if iconf -b welcome; then
	instantwelcome
fi &

# user declared autostart
if [ -e ~/.instantautostart ]; then
	bash ~/.instantautostart
fi
