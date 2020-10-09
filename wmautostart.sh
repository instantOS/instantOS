#!/bin/bash

# gets executed every time the window manager restarts

if iconf defaultlayout
then
    instantwmctrl prefix 1
    sleep 0.1
    instantwmctrl layout "$(iconf defaultlayout)"
fi
