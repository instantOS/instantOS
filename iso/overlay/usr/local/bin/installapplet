#!/usr/bin/env python3

#################################################
## systray applet to start instantOS installer ##
#################################################


import os
import gi
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')
from gi.repository import Gtk as gtk, AppIndicator3 as appindicator


def main():
    indicator = appindicator.Indicator.new(
        "customtray", "calamares", appindicator.IndicatorCategory.APPLICATION_STATUS)
    indicator.set_status(appindicator.IndicatorStatus.ACTIVE)
    indicator.set_menu(menu())
    gtk.main()


def menu():
    menu = gtk.Menu()

    command_one = gtk.MenuItem(label='install instantOS')
    command_one.connect('activate', install)
    menu.append(command_one)

    menu.show_all()
    return menu


def install(_):
    os.system('/usr/bin/instantosinstaller')


if __name__ == "__main__":
    main()
