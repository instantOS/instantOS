# instantOS iso build

## What this is

A fork of the releng archiso profile. 

## How to update this

Manually copy `/usr/share/archiso/configs/releng/` here. 
Then use a git client to figure out what changed upstream, and manually revert
the stuff which got overwritten even though instantOS should have it changed.
Anything interesting which changed upstream will stand out in the git diff. 

The live-image customizations belong in `overlay/`, which is their single source
of truth. `build.sh` copies the upstream-derived `releng/` profile to its build
directory and then applies `overlay/` to that temporary copy. Do not duplicate
overlay files under `releng/airootfs/`. `update.sh` only refreshes the upstream
releng base; it does not modify or copy the overlay.

The live user is configured for GDM autologin and its default instantOS
dotfiles repository is cloned and applied with `ins dot` by `instantos-setup`.
The welcome app starts via XDG autostart and launches the TUI installer in a
terminal.

At live-session startup, `liveautostart` refreshes the package-managed `ins`
package before Welcome and the installer applet are launched. If the machine is
offline or the refresh fails, the version bundled in the ISO remains available.
