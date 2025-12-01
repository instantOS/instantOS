# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the instantOS ISO build repository - tools for creating a live installation ISO for instantOS, an Arch Linux derivative distribution. The project uses archiso as the underlying build system but with significant customizations for the instantOS experience.

## Build System

### Primary Build Command
```bash
./build.sh
```

This script:
- Requires running on an instantOS installation (or Arch/Manjaro with `instantinstall archiso`)
- Uses the system's archiso installation from `/usr/share/archiso/configs/releng/`
- Builds to `./build/` directory by default (configurable via `ISO_BUILD` env var)
- Produces final ISO in `build/iso/`

### Key Build Process
1. Clones and manages dependencies: instantARCH, instantOS, liveutils, instantLOGO repositories
2. Copies upstream archiso releng profile to temp directory
3. Applies instantOS customizations:
   - Adds instantOS repository to pacman.conf
   - Appends package lists from instantARCH
   - Sets up syslinux bootloader with custom branding
   - Copies live assets (wallpapers, splash screen)
4. Executes deprecated `customize_airootfs.sh` in chroot for live environment setup
5. Runs `mkarchiso` to generate final ISO

## Architecture

### Current Implementation (Deprecated)
The build system relies on the deprecated `customize_airootfs.sh` script (removed in archiso v60) which runs in a chroot environment to:
- Create user `instantos` with password `instantos`
- Setup LightDM autologin
- Configure sudo access
- Apply instantOS theming and dotfiles
- Install development tools via external scripts

### Migration Plan (See plan.md)
A comprehensive migration strategy exists to modernize the build process:
- Move from dynamic chroot scripts to static file overlays
- Use modern archiso features (pacman hooks, declarative configs)
- Maintain upstream compatibility by patching releng profile dynamically
- Preserve all existing functionality while improving maintainability

## Key Components

### build.sh
Main build orchestrator that handles:
- Dependency management via `ensurerepo()` function
- Package list aggregation from multiple sources
- Bootloader customization (syslinux splash, timeout)
- Asset management (wallpapers, logos)

### airootfs/
Contains static files that get copied to the live environment:
- `root/customize_airootfs.sh` - deprecated chroot customization script
- `etc/instantos/` - version and configuration files
- `usr/` - overlay for system files

### syslinux/
Bootloader configuration and assets:
- Custom splash.png branding
- Modified timeout settings (100 instead of default)

## External Dependencies

The build process dynamically fetches and integrates:
- **instantARCH**: Installation framework and package definitions
- **instantOS**: Main distribution configuration and theming
- **liveutils**: Live environment assets and wallpapers
- **instantLOGO**: Branding assets for bootloader

## Development Notes

### Building Requirements
- Must run on instantOS installation or compatible Arch-based system
- Requires `instantinstall archiso` for archiso dependencies
- Needs internet access for git repository cloning
- Requires sudo privileges for `mkarchiso` execution

### Testing
- Test builds should be done in a clean environment
- The `build/` directory is completely removed before each build
- Workspace is cached in `build/workspace/` for faster subsequent builds

### Current Limitations
- Uses deprecated archiso chroot scripts
- Fragile dependency on external git repositories
- Limited error handling for network issues
- Hard-coded repository URLs and configurations

## Important Files

- `build.sh` - Main build script (136 lines)
- `airootfs/root/customize_airootfs.sh` - Deprecated live environment setup
- `plan.md` - Comprehensive migration strategy documentation
- `syslinux/splash.png` - Bootloader branding asset