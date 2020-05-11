#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd
echo "installing instantOS tools"

# laptop specific stuff
if acpi | grep -q '.' &>/dev/null; then
    # config file to indicate being a laptop
    echo "device appears to be a laptop"
    iconf -i islaptop 1
fi

# needed for nm-applet start
if lspci | grep -Eiq '(wifi|wireless)'; then
    echo "device has wifi capabilities"
    iconf -i haswifi 1
    iconf -i wifiapplet 1
fi

# needed to disable bluetooth service
if lsusb | grep -iq 'bluetooth'; then
    echo "device has bluetooth"
    iconf -i hasbluetooth 1
fi

instantmouse gen

mkdir ~/instantos
iconf -i userinstall 1
