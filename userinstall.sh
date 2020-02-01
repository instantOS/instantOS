#!/usr/bin/env bash

#############################################
## installs all instantOS tools            ##
#############################################

cd "$HOME"

echo "installing instantOS tools"

RAW="https://raw.githubusercontent.com"
LINK="$RAW/instantos/instantos/master"

cd "$HOME"

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
