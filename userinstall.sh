#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd || echo "ERROR: could not go to HOME"
echo "installing instantOS tools"

# laptop specific stuff
if acpi | grep -q '.' &>/dev/null; then
    # config file to indicate being a laptop
    echo "device appears to be a laptop"
    iconf -i islaptop 1
fi

# needed for nm-applet start
while read; do
    case $REPLY in
        *[Ww][Ii][Ff][Ii]*|*[Ww][Ii][Rr][Ee][Ll][Ee][Ss][Ss]*)
            echo "device has wifi capabilities"
            iconf -i haswifi 1
            iconf -i wifiapplet 1 ;;
    esac
done <<< "$(lspci)"

# needed to disable bluetooth service
while read; do
    case $REPLY in
        *[Bb][Ll][Uu][Ee][Tt][Oo][Oo][Tt][Hh]*)
            echo "device has bluetooth"
            iconf -i hasbluetooth 1 ;;
    esac
done <<< "$(lsusb)"

# change some behaviour like light for setting brightness
if iconf -r hasnvidia; then
    iconf -i hasnvidia 1
    iconf -i uselight 1
fi

if ! iconf -i nodesktophide && ! iconf -i desktophidden; then
    instantutils hide
fi

instantmouse gen

mkdir ~/instantos
mkdir -p ~/.config/instantos

if ! iconf -i readroot; then
    /usr/share/instantutils/setup/readroot && iconf -i readroot 1
fi

iconf -i userinstall 1
