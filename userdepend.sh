#!/bin/bash

# install user dependencies for instantOS

echo "installing user dependencies for $(whoami)"

if ! [ -e ~/.autojump ]; then
    echo "installing autojump"
    rm -rf /tmp/autojump
    mkdir /tmp/autojump
    cd /tmp/autojump
    git clone --depth=1 git://github.com/wting/autojump.git
    cd autojump
    chmod +x install.py
    ./install.py | grep '\[\[ -s ' >>~/.bashrc
    cd ..
    rm -rf /tmp/autojump
fi

if ! grep 'autojump' ~/.bashrc; then
    echo "installing autojump configuration"
    echo "[[ -s $HOME/.autojump/etc/profile.d/autojump.sh ]] && source $HOME/.autojump/etc/profile.d/autojump.sh" >>~/.bashrc
fi
