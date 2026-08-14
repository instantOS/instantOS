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

The live image version in `/etc/instantos/version` is generated at build time
from `SOURCE_DATE_EPOCH`, or from the current time when it is unset. The same
UTC date is used by the archiso profile for its ISO version and label.

The live user is configured for GDM autologin and its default instantOS
dotfiles repository is cloned and applied with `ins dot` by `instantos-setup`.
The welcome app starts via XDG autostart and launches the TUI installer in a
terminal.

At live-session startup, `liveautostart` refreshes the package-managed `ins`
package before Welcome and the installer applet are launched. If the machine is
offline or the refresh fails, the version bundled in the ISO remains available.

## Build-time inputs and verification

`build.sh` fetches the dotfiles, instantTOOLS, and liveutils repositories before
starting `mkarchiso`. Their resolved commits are recorded in
`/usr/share/instantos/build-sources.env`. The package hook configures the live
system exclusively from those bundled sources, so it does not depend on DNS or
network access inside the temporary airootfs chroot.

The hook writes `/opt/instantos/.setup-done` only after all customizations have
been applied and checked. Failures are recorded in
`/opt/instantos/.setup-failed` for diagnostics. Pacman continues running its
remaining post-transaction hooks after a hook failure, so `build.sh` does not
trust the package transaction alone. After `mkarchiso` returns, `verify.sh`
extracts the root squashfs from the finished ISO and verifies the marker, live-user
dotfiles, instantTOOLS installation, login configuration, source revisions,
and removal of the build-only package hook. A missing or incomplete instantOS
customization therefore fails the entire ISO build.

Set `DOTFILES_REF`, `INSTANTTOOLS_REF`, or `LIVEUTILS_REF` to build from a
specific branch, tag, or commit. Their corresponding `*_BRANCH` variables
control the branch retained in the bundled Git checkout and default to `main`.
