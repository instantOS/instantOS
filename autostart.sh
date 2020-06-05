#!/usr/bin/env bash

###############################################
## script for instantOS autostart            ##
###############################################

# run userinstall to determine device properties
if ! iconf -i userinstall; then
	/usr/share/instantutils/userinstall.sh
fi

# architecture detection
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
instantdotfiles

if ! iconf -i rangerplugins; then
	mkdir instantos
	echo "installing ranger plugins"
	mkdir -p ~/.config/ranger/plugins
	cp -r /usr/share/rangerplugins/* ~/.config/ranger/plugins/

fi

# find out if it's a live session
if [ -e /usr/share/liveutils ] &>/dev/null; then
	ISLIVE="True"
	echo "live session detected"

	# fix resolution on virtualbox
	if sudo dmidecode | grep -iq 'virtualbox'; then
		bash /opt/instantos/menus/dm/tv.sh
	fi
fi

# fix small graphical glitch on status bar startup
NMON=$(iconf names | wc -l)
for i in $(eval "echo {1..$NMON}"); do
	echo "found monitor $i"
	xdotool key super+comma
	if iconf -i nobar; then
		xdotool key super+b
	fi
done &

if [ -n "$ISRASPI" ]; then
	# enable double drawing for moving floating windows
	# greatly increases smoothness
	iconf -i highfps 1
	if ! [ -e ~/.config/instantos/israspi ]; then
		echo "marking machine as raspi"
		mkdir -p ~/.config/instantos
		touch ~/.config/instantos/israspi
		# logo does not work on raspi
		iconf -i nologo 1
	fi
fi

if iconf -i islaptop; then
	export ISLAPTOP="true"
	echo "laptop detected"
else
	echo "not a laptop"
fi

if ! [ -e /opt/instantos/potato ]; then
	# optional blur
	if iconf -i blur; then
		picom --experimental-backends &
	else
		picom &
	fi
else
	echo "your computer is a potato, no compositing for you"
fi

if ! iconf -i notheming; then
	instantthemes a
	xrdb ~/.Xresources
	iconf -i instantthemes 1
fi

# dynamically switch between light and dark gtk theme
DATEHOUR=$(date +%H)
if [ "$DATEHOUR" -gt "20" ] || [ "$DATEHOUR" -lt "7" ]; then
	instantthemes d &
	touch /tmp/instantdarkmode
	[ -e /tmp/instantlightmode ] && rm /tmp/instantlightmode
else
	instantthemes l &
	touch /tmp/instantlightmode
	[ -e /tmp/instantdarkmode ] && rm /tmp/instantdarkmode
fi &

mkdir -p /tmp/notifications &>/dev/null
if ! pgrep dunst; then
	while :; do
		# wait for theming before starting dunst
		if [ -e /tmp/instantdarkmode ] || [ -e /tmp/instantlightmode ]; then
			dunst
		fi
		sleep 2
	done &
fi

onlinetrigger() {
	instantwallpaper &
}

# set up oh-my-zsh config if not existing already
instantshell &
if ! [ iconf -i userinstall ]; then
	bash /usr/share/instantutils/userinstall.sh
fi

if [ -z "$ISLIVE" ]; then
	echo "not a live session"
	if [ -e /opt/instantos/installtrigger ]; then
		zenity --info --text "finishing installation in background" &
		sudo instantpostinstall
		pkill zenity
	fi

	cd ~/instantos
	if ! iconf -i max; then
		instantmonitor
	fi

	if [ -e ~/instantos/monitor.sh ]; then
		bash ~/instantos/monitor.sh &
	elif [ -e ~/.config/autorandr/instantos/config ]; then
		autorandr instantos &
	fi

	if ping archlinux.org -c 2; then
		onlinetrigger
	else
		# fall back to already installed wallpapers
		instantwallpaper offline
		for i in $(seq 10); do
			if ping archlinux.org -c 2; then
				onlinetrigger
				break
			else
				sleep 10
			fi
		done
	fi &

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

	# read cursor speed
	if iconf mousespeed; then
		echo "setting mousespeed"
		instantmouse s "$(iconf mousespeed)"
	fi

	if ! iconf -i noconky; then
		shuf /usr/share/instantwidgets/tooltips.txt | head -1 >~/.cache/tooltip
		conky -c /usr/share/instantwidgets/tooltips.conf &
	fi

else
	echo "live session detected"
	instantmonitor
	iconf -b welcome 1
	iconf -i wifiapplet 1
	instantwallpaper set /usr/share/instantwallpaper/defaultphoto.png
	conky -c /usr/share/instantwidgets/install.conf &
	sleep 0.3
	while :; do
		if ! pgrep python; then
			installapplet
		fi &
		sleep 6m
	done &
	sleep 1
fi

if iconf -i highfps; then
	xdotool key super+alt+shift+d
fi

# make built in status optional
if ! iconf -i nostatus; then
	source /usr/bin/instantstatus &
fi

lxpolkit &
xfce4-power-manager &

while iconf -i wifiapplet:; do
	if ! pgrep nm-applet; then
		nm-applet &
	fi
	sleep 6m
done &

# welcome greeter app
if iconf -b welcome; then
	instantwelcome
fi &

# prompt to fix configuration if installed from the AUR
if ! iconf -i norootinstall && [ -z "$ISLIVE" ]; then
	if ! command -v imenu || ! command -v instantmenu; then
		notify-send "please install instantmenu and imenu"
	else
		if ! [ -e /opt/instantos/rootinstall ]; then
			imenu -m "instantOS is missing some configuration"
			while ! [ -e /tmp/rootskip ]; do
				if imenu -c "would you like to fix that?"; then
					touch /tmp/topinstall
					instantsudo bash -c "instantutils root && touch /opt/instantos/rootinstall && echo done"
					touch /tmp/rootskip
				else
					if imenu -c "Are you sure? this will prevent parts of instantOS from functioning correctly"; then
						touch /tmp/rootskip
					fi
				fi

			done
		fi
	fi
fi

# desktop icons
if iconf -i desktopicons; then
	rox --pinboard Default
fi &

# user declared autostart
if [ -e ~/.instantautostart ]; then
	bash ~/.instantautostart
fi
