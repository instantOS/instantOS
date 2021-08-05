#!/bin/bash

# gets executed every time the window manager restarts

# applies various wm settings

if iconf defaultlayout; then
    instantwmctrl prefix 1
    sleep 0.1
    instantwmctrl layout "$(iconf defaultlayout)"
fi

confkey() {
    [ -n "$2" ] || return
    iconf -i "$1" || return
    xdotool key "$2"
}

if iconf -i noanimations; then
    instantwmctrl animated 1
fi

confkey highfps "super+alt+shift+d"
