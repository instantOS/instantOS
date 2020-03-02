#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd
echo "installing instantOS tools"

# laptop specific stuff
if acpi | grep -q '[0-9]%' &>/dev/null; then
    # config file to indicate being a laptop
    echo "device appears to be a laptop"
    touch .cache/islaptop
fi

# needed for nm-applet start
if lspci | grep -Eiq '(wifi|wireless)'; then
    echo "device has wifi capabilities"
    touch .cache/haswifi
fi

cd
mkdir -p instantos/notifications &>/dev/null

cd instantos
rm -rf wallpapers
mkdir wallpapers

# set instantwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=instantwm' >>.dmrc
