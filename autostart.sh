#!/usr/bin/env bash

###############################################
## script for instantOS autostart            ##
###############################################

# run userinstall to determine device properties
if ! iconf -i userinstall; then
	/usr/share/instantutils/userinstall.sh
	iconf -i userinstall 1
fi

# architecture detection
if [ -z "$1" ]; then
	if uname -m | grep -q '^arm'; then
		export ISRASPI=true
	fi

	if [ "$(ps aux | grep bash | grep instantautostart | wc -l)" -gt 3 ]; then
		echo "already running"
		exit
	fi
else
	echo "forced run"
fi

cd
command -v instantdotfiles && instantdotfiles

if ! iconf -i rangerplugins && command -v rangerplugins; then
	mkdir instantos
	echo "installing ranger plugins"
	mkdir -p ~/.config/ranger/plugins
	cp -r /usr/share/rangerplugins/* ~/.config/ranger/plugins/
	iconf -i rangerplugins 1
fi

# find out if it's a live session
if [ -e /usr/share/liveutils ] &>/dev/null; then
	ISLIVE="True"
	echo "live session detected"
fi

if iconf -i islaptop; then
	export ISLAPTOP="true"
	echo "laptop detected"
else
	echo "not a laptop"
fi

islive() {
	if [ -n "$ISLIVE" ]; then
		return 0
	else
		return 1
	fi
}

# optionally disable status bar
if iconf -i nobar; then
	NMON=$(iconf names | wc -l)
	for i in $(eval "echo {1..$NMON}"); do
		echo "found monitor $i"
		xdotool key super+comma
		xdotool key super+b
	done &
fi

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

if ! iconf -i notheming; then
	instantthemes a
	xrdb ~/.Xresources
	iconf -i instantthemes 1

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
else
	touch /tmp/instantlightmode
fi

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
iconf -i nozsh || instantshell &

# fix resolution on virtual machine
if ! iconf -i novmfix && grep -q 'hypervisor' /proc/cpuinfo; then
	# indicator file only exists on kvm/QEMU on amd
	if [ -e /opt/instantos/kvm ]; then
		iconf -i highfps 1
		if lshw -c video | grep -i 'qxl' || xrandr | grep -i '^qxl'; then
			iconf -i qxl 1
			# iconf -i noanimations 1
			if ! iconf -i potato && ! iconf -i nopotato; then
				if echo "please set your video card to virtio or passthrough
QXL on AMD on QEMU/kvm has been known to cause a severe Xorg memory leak. 
Disabling compositing makes this somewhat bearable,
but switching really is recommended.
(or switch to virtualbox, no issues there...)
Disable compositing for this VM?" | imenu -C; then
					iconf -i potato 1
					pkill picom
				else
					if ! imenu -c "ask again next time?"; then
						iconf -i nopotato 1
					fi
				fi
			fi
		else
			iconf -i qxl 1
		fi
	fi

	if ! [ -e /opt/instantos/guestadditions ]; then
		if echo "virtual machine detected.
Would you like to switch to a 1080p resolution?" | imenu -C; then
			echo "applying virtual machine workaround"
			/usr/share/instantassist/assists/t/v.sh
		else
			if ! imenu -c "ask again next session"; then
				iconf -i novmfix 1
			fi
		fi
	fi
fi

if ! islive; then
	echo "not a live session"
	if [ -e /opt/instantos/installtrigger ]; then
		zenity --info --text "finishing installation in background" &

		# ask for password if postinstall already ran
		if ! timeout 2 sudo echo test; then
			instantsudo instantpostinstall
			sudo rm /opt/instantos/installtrigger
		else
			sudo instantpostinstall
		fi

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

	if checkinternet; then
		onlinetrigger
	else
		# fall back to already installed wallpapers
		instantwallpaper offline
		for i in $(seq 10); do
			if checkinternet; then
				onlinetrigger
				break
			else
				sleep 10
			fi
		done
	fi &

	# apply keybpard layout
	if iconf layout; then
		setxkbmap -layout "$(iconf keyboard)"
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

	echo "disabling compositing for qxl graphics"
	if lshw -c video | grep -i 'qxl' || xrandr | grep -i '^qxl'; then
		iconf -i potato 1
	fi

	sudo systemctl start NetworkManager

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

# make built in status optional
if ! iconf -i nostatus; then
	source /usr/bin/instantstatus &
fi

iconf -i potato || ipicom &

while :; do
	lxpolkit
done &

xfce4-power-manager &

while iconf -i wifiapplet:; do
	if ! pgrep nm-applet; then
		nm-applet &
	fi
	sleep 6m
done &

while iconf -i bluetoothapplet:; do
	if ! pgrep blueman-applet; then
		blueman-applet &
	fi
	sleep 6m
done &

# welcome greeter app
if iconf -b welcome; then
	instantwelcome
fi &

# prompt to fix configuration if installed from the AUR
if ! iconf -i norootinstall && ! islive; then
	if ! command -v imenu || ! command -v instantmenu; then
		notify-send "please install instantmenu and imenu"
	else
		if ! [ -e /opt/instantos/rootinstall ]; then
			imenu -m "instantOS is missing some configuration"
			while ! [ -e /tmp/rootskip ]; do
				if imenu -c "would you like to fix that?"; then
					touch /tmp/topinstall
					instantsudo bash -c "instantutils root"
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

# displays message user opens the terminal for the first time
if ! iconf -i nohelp; then
	if ! grep -q 'instantterminalhelp' ~/.zshrc; then
		echo '[[ $- == *i* ]] && instantterminalhelp' >>~/.zshrc
	fi
fi

if iconf -i highfps; then
	xdotool key super+alt+shift+d
fi

if iconf -i noanimations; then
	xdotool key super+alt+shift+s
fi

# desktop icons
if iconf -i desktopicons; then
	rox --pinboard Default
fi &

# optional udiskie
if iconf -i udiskie; then
	command -v udiskie && udiskie -t &
fi

# user declared autostart
if [ -e ~/.instantautostart ]; then
	bash ~/.instantautostart
fi
