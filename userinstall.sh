#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd
echo "installing instantOS tools"

# laptop specific stuff
if acpi | grep -q '[0-9]%' &>/dev/null; then
    # config file to indicate being a laptop
    touch .cache/islaptop
fi

cd
mkdir -p instantos/notifications &>/dev/null

cd instantos
rm -rf wallpapers
mkdir wallpapers

# set instantwm as default for lightdm
echo '[Desktop]' >.dmrc
echo 'Session=instantwm' >>.dmrc
