# instantOS iso build

## What this is

A fork of the releng archiso profile. 

## How to update this

Manually copy `/usr/share/archiso/configs/releng/` here. 
Then use a git client to figure out what changed upstream, and manually revert
the stuff which got overwritten even though instantOS should have it changed.
Anything interesting which changed upstream will stand out in the git diff. 

The live-image customizations belong in `overlay/`; `update.sh` reapplies that
directory after refreshing the upstream releng profile. Keep the matching files
under `releng/airootfs/` synchronized before building.

The live user is configured for GDM autologin and its default instantOS
dotfiles repository is cloned and applied with `ins dot` by `instantos-setup`.
The welcome app starts via XDG autostart and launches the TUI installer in a
terminal.

