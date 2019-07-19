#!/usr/bin/env bash
echo "installing paperbenni's suckless suite"

gclone() {
    git clone --depth=1 https://github.com/paperbenni/"$1".git
}

mkdir -p ~/.local/share/fonts

pushd ~/.local/share/fonts
if ! [ -e monaco.ttf ]; then
    wget https://github.com/todylu/monaco.ttf/raw/master/monaco.ttf
fi
popd

rm -rf ~/suckless
mkdir ~/suckless
cd ~/suckless

gclone dwm
gclone dmenu
gclone st
gclone slock

wget https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
sudo mv dwm.desktop /usr/share/xsessions/

for FOLDER in ./*; do
    if ! [ -d "$FOLDER" ]; then
        echo "skipping $FOLDER"
        continue
    fi
    pushd "$FOLDER"
    rm config.h
    make
    sudo make install
    popd
done

if ! [ -z "$1" ]; then
    curl https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
fi

# install window switcher
LINK="https://raw.githubusercontent.com/paperbenni/suckless/master"

curl "$LINK/dswitch" | sudo tee /usr/local/bin/dswitch
sudo chmod +x /usr/local/bin/dswitch

# install win + a menus for screenshots
curl https://raw.githubusercontent.com/paperbenni/menus/master/install.sh | bash
