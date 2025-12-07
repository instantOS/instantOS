#!/bin/bash

# gets executed every time the window manager restarts

# applies various wm settings

if iconf defaultlayout; then
    instantwmctl prefix 1
    sleep 0.1
    instantwmctl layout "$(iconf defaultlayout)"
fi

confkey() {
    [ -n "$2" ] || return
    iconf -i "$1" || return
    xdotool key "$2"
}

if iconf -i noanimations; then
    instantwmctl animated 1
fi

confkey highfps "super+alt+shift+d"
