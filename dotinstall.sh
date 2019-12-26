#!/bin/bash
echo "installing dotfiles"
curl -s https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
echo "installing suckless tools"
curl -s https://raw.githubusercontent.com/paperbenni/suckless/master/install.sh | bash
