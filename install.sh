#!/usr/bin/env bash
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

if grep -i "Arch" </etc/os-release; then
    mkdir slock-git
    cd slock-git
    wget https://raw.githubusercontent.com/paperbenni/suckless/master/slock/PKGBUILD
    makepkg -Acs
    sudo pacman -U *.pkg.tar.xz
else
    gclone slock
fi

gclone st
wget https://raw.githubusercontent.com/paperbenni/suckless/master/dwm.desktop
sudo mv dwm.desktop /usr/share/xsessions/

for FOLDER in ./*; do
    if ! [ -d "$FOLDER" ]; then
        echo "skipping $FOLDER"
        continue
    fi
    case $FOLDER in
    slock)
        pushd
        ;;
    esac
    pushd "$FOLDER"
    rm config.h
    make
    sudo make install
    popd
done

if ! [ -z "$1" ]; then
    curl https://raw.githubusercontent.com/paperbenni/dotfiles/master/install.sh | bash
fi
