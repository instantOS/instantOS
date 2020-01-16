#!/bin/bash

# install user dependencies for instantOS

echo "installing user dependencies for $(whoami)"

if ! grep -q 'autojump' ~/.bashrc; then
    echo "installing autojump"
    mkdir /tmp/autojumps
    cd /tmp/autojump
    git clone --depth=1 git://github.com/wting/autojump.git
    cd autojump
    chmod +x install.py
    ./install.py | grep '\[\[ -s ' >>~/.bashrc
    cd ..
    rm -rf /tmp/autojump
fi
