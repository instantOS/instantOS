#!/bin/bash
# central installer script for pb suckless

if cat /etc/os-release | grep -Eiq 'name.*(arch|manjaro|ubuntu)'; then
    echo "
      ___.                           __   .__                        
______\_ |__     ________ __   ____ |  | _|  |   ____   ______ ______
\____ \| __ \   /  ___/  |  \_/ ___\|  |/ /  | _/ __ \ /  ___//  ___/
|  |_> > \_\ \  \___ \|  |  /\  \___|    <|  |_\  ___/ \___ \ \___ \ 
|   __/|___  / /____  >____/  \___  >__|_ \____/\___  >____  >____  >
|__|       \/       \/            \/     \/         \/     \/     \/ 
"
else
    echo "distro not supported"
    echo "supported are: Arch, Manjaro, Ubuntu"
    exit
fi

echo "installing dependencies"
curl -s https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
echo "installing dotfiles"
curl -s https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
echo "installing suckless tools"
curl -s https://raw.githubusercontent.com/paperbenni/suckless/master/install.sh | bash
