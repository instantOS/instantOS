# Offline instantOS installer — feasibility study & design

**Status:** research complete; no production code changed yet. Claims marked ✅ are
backed by experiments run in Docker (`archlinux:base-devel`, image `arch-offline:prep`,
container `ins-prep`); scripts live in `/tmp/opencode/offline-exp/` (Appendix A maps every
script to its claim). Goal of this document: answer *can instantOS install without
internet, using only its own ISO — and what is the most idiomatic way to build it.*

---

## 0. Verdict (TL;DR)

- **Yes — feasible and proven at the pacman level.** Every hard network dependency in
  the installer is a "fetch packages/metadata/config from the internet" dependency, and
  pacman natively serves all of them from a local `file://` repository. No separate
  offline installer binary is needed; `ins` needs a handful of conditional changes.
- **Recommended design (Option A):** the offline ISO carries a *bundle* — a local
  pacman repository — at ISO root. The live system, `pacstrap`, and every in-chroot
  pacman transaction use
  `Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch` **first**, with the
  normal https mirrors kept as fallback. The chroot sees the bundle through one explicit
  `mount --bind`.
- Proven end-to-end at the pacman layer ✅: offline `pacstrap` (network fully disabled),
  in-chroot `pacman -Sy` / `-S` from a bind-mounted bundle, server-ordering fallback
  (db level **and** package level), signature/checksum integrity preserved offline
  (same-size tampering rejected), and correct negative controls (a package missing from
  the bundle fails loudly offline instead of silently installing something else).
- **Bundle size:** 2.4 GiB for the union of all boolean wizard options (888 packages);
  **decided scope = full enum-union** (§10.1): ~2.6–3.2 GiB once enum alternatives
  (kernels, display managers, desktops) and live-side runtime dependencies are unioned
  in. Current release ISO is
  1,938,161,664 B (~1.81 GiB) → **offline ISO ≈ 4.4–5.0 GiB**, which **cannot be a
  GitHub release asset** (2 GiB/file cap; no bundle tier fits under the ~200 MB the
  current ISO leaves free) → offline ISO is published on **SourceForge**, while the
  online ISO stays on GitHub releases (both artifacts ship, §10.9). Nothing in the
  design shrinks the ISO — placement
  tricks only dodge an *internal* ISO9660 4 GiB single-file limit (§4.2), they do
  not remove the bundle's bytes.
- **Three biggest engineering gotchas:**
  1. The bundle must **not** live inside `airootfs.sfs` — ISO9660's 4 GiB single-file
     limit would be hit (§4.2). It goes at ISO root and is injected post-build.
  2. `arch-chroot` only auto-binds `/dev /proc /sys /run`; the bundle needs its own
     `mount --bind` into `/mnt` (the experiments had to do this manually too ✅).
  3. **Every enabled pacman repo must be bundled or stay disabled** — one missing repo
     poisons the whole `pacman -Sy`, even if all needed packages are present.
- Roughly a day of instantCLI work + a day of ISO-build work + e2e wiring (§8).

---

## 1. How it works today

### 1.1 Live ISO build (`instantOS/iso/`)

| File | Role / facts |
|---|---|
| `build.sh` | `:36` copies `releng/` → build profile; `:38` merges `overlay/` over `airootfs/` (**merge order matters — overlay wins**); `:49–100` `fetch_source_repo` clones **dotfiles, instantTOOLS, liveutils** and `:86` stores the dotfiles *git repo* at `airootfs/usr/share/instantos/build-inputs/dotfiles` (already offline-usable!); `:118–120` runs `mkarchiso`; `:129` runs `verify.sh`. No hook exists for extra ISO-root files — `mkarchiso` stages only the profile (§4.6 for the injection plan). |
| `releng/pacman.conf` | Used at build time (and becomes the build chroot's conf). `:87–89` has `[instant] / SigLevel = Optional TrustAll / Server = https://instantos.io/packages`. Stock `#CheckSpace`, `#ParallelDownloads` etc. |
| `releng/packages.x86_64` | Live ISO contents. Live-side installer deps present: `git` (:143), `fzf` (:142), `ntfsprogs` (:88), `btrfs-progs` (:11), `util-linux` (via `base`), `arch-install-scripts` (:3), plus `instantdepend`/`instantos`. **Missing: `gum`, `ntfs-3g`** — the installer installs these on the live system at ask time (§2), i.e. they are a runtime network dependency unless bundled. |
| `releng/profiledef.sh` | `:14–15` `airootfs_image_type=squashfs`, `-comp xz -Xbcj x86`. Relevant to sizing: package archives are already zstd-compressed, so xz gains ~nothing on them (incompressible) → they add their raw size to `airootfs.sfs` (§4.2). |
| `releng/airootfs/` | Skeleton only (shadow, resolv.conf, `etc/pacman.d/hooks`, …). **No shipped `mirrorlist`, no `etc/pacman.conf`** → the live system's mirrorlist is whatever pacstrap copies from the *build host* (non-deterministic) and the live `pacman.conf` comes from pacstrap/`base` propagation (open question §10.4). |
| `overlay/` | instantOS live additions: `usr/local/bin/{liveautostart,instantos-setup,installapplet}`, `etc/pacman.d/hooks/90-instantos-setup.hook`, XDG autostart entries, sudoers, profile.d. This is where an offline-only overlay would slot in. |
| `verify.sh` | Extracts `airootfs.sfs` from the ISO with `bsdtar`, asserts setup markers, build-source manifest, dotfiles/greetd config (bsdtar can also read ISO-root files → usable for bundle verification, §4.6). Does **not** boot the image; boot testing lives in the e2e suite. |
| `.github/workflows/iso.yml`, `justfile` | Release flow: `build-iso`, `checksums`, `download-iso`. Latest published ISO: **1,938,161,664 B (1.81 GiB)**. |

### 1.2 Installer (`instantCLI`, `src/arch/`)

Flow: `ins arch install` (`cli/commands/install.rs:67`) →
battery confirm → **`ensure_interactive_internet` (`:40`, called `:89`, loops on nmtui,
aborts without network)** → `ensure_root` → distro/arch checks →
`ask` (wizard) → `exec` → `finished`.

Ask phase:

- **`ensure_internet`** (`cli/commands/ask.rs:138`, called `:321`): hard `bail!` when
  `system_info.internet_connected` is false (tests at `:363–389`).
- **`install_live_iso_dependencies`** (`ask.rs:146–179`): on a live ISO installs
  `fzf, git, gum, cfdisk(util-linux), btrfs-progs, ntfsprogs, ntfs-3g` in one
  `pacman -S` → network (needs `gum` + `ntfs-3g` from the bundle, §4.6).
- **Mirror region question**: `MirrorlistProvider::provide` (`mirrors.rs:294`) fetches
  the region list from archlinux.org (degrades to "skip question" on failure `:304–312`).
- **Geo data** fetch: soft (skippable).

Execute phase — steps `Disk → Base → Fstab → Config → Bootloader → Post`:

- **Base** (`execution/base.rs:8`): `setup_mirrors` (`:21–56`) — fetch region/fallback
  mirrorlist and **overwrite `/etc/pacman.d/mirrorlist` (`:52`)**. Important: the
  fallback chain (`mirrors.rs:128–186`) always ends in
  `validate_and_prioritize_mirrors` (`:247`) which **probes latency over the network** —
  so even the "local mirrorlist fallback" fails offline. Then `run_pacstrap`
  (`base.rs:148–192` → `execution/pacman.rs:155`, retry ×10). `pacstrap` is invoked
  **without `-C`/`-P`**, so it copies the *live* mirrorlist into the target — the live
  mirrorlist is the single leverage point for the whole install.
- **Chroot**: `setup_chroot` (`execution/mod.rs:684`) copies the `ins` binary, config
  and state into `/mnt`, then steps re-invoke themselves under `arch-chroot /mnt`
  (`mod.rs:588`; `paths.rs:8` `CHROOT_MOUNT = /mnt`).
- **In-chroot setup** (`execution/setup.rs`):
  - `:150–159` `setup_instant_repo` appends `[instant]` + writes
    `/etc/pacman.d/instantmirrorlist` from the compiled-in constant
    `INSTANT_MIRRORLIST` (`common/pacman.rs:5`, `:40–46` — https instantserver), then
    runs **`pacman -Sy`** → fails offline today.
  - `:187–230` `setup_user_dotfiles` clones
    `INSTANTOS_DOTFILES_REPO = https://github.com/instantOS/dotfiles` (`:11`, cmd `:205`)
    → fails offline today.
  - `:236–246` wallpaper: already best-effort (soft).
  - Multilib enablement: `common/pacman.rs:52` (fresh installs always enable multilib
    during Config → **multilib must always be bundled**).
- **Unmount sites** for `/mnt`: `execution/disk/filesystem.rs:69`, `disks.rs:181`, plus
  the success-path cleanup to be located during implementation (§4.5.6).

Sanity check used throughout this study: `cargo build --bin ins` +
`ins arch exec --dry-run -f <questions>` prints the exact package plan
(note: the old `--trust-config` flag no longer exists). The full-profile run is
archived at `/tmp/opencode/offline-exp/dryrun-full.txt`.

---

## 2. Network-dependency inventory

| # | Dependency | Site | Kind | Offline solution |
|---|---|---|---|---|
| 1 | "No internet" abort loop (nmtui) | `install.rs:40/:89` | hard | Skip when bundle detected; optionally still offer nmtui |
| 2 | "No internet" bail | `ask.rs:138/:321` | hard | Same as #1 |
| 3 | Live-deps `pacman -S` (`gum`, `ntfs-3g` not on live ISO) | `ask.rs:146–179` | hard | Works unchanged once live mirrorlist has `file://` first **and** both packages are in the bundle |
| 4 | Mirror region fetch | `mirrors.rs:54/:294` | hard (degrades) | Offline: read bundled `regions/` snapshot (same parser); missing snapshot → existing `MirrorRegionsFetchFailed` skip |
| 5 | Mirrorlist fetch + **latency probing** (even the local-file fallback probes!) | `mirrors.rs:128–260`, `base.rs:21–56` | hard | Offline: bypass chain entirely — keep the shipped `file://`-first mirrorlist |
| 6 | `pacstrap` package downloads (172–180 pkgs minimum) | `base.rs:148` → `execution/pacman.rs:155` | hard | Served from bundle via live mirrorlist ✅ |
| 7 | Target `pacman -Sy` for `[instant]` | `setup.rs:150–159` + `common/pacman.rs:5` | hard | `instantmirrorlist` gets `file://` line first (visible in chroot through bind) ✅ |
| 8 | GitHub dotfiles clone | `setup.rs:187–230` (`:11`, `:205`) | hard | Clone from the dotfiles snapshot **already shipped** at `/usr/share/instantos/build-inputs/dotfiles` (`iso/build.sh:80–86`); copy into chroot, rewrite origin URL afterwards |
| 9 | Geo data fetch | geo question provider | soft | Skip offline |
| 10 | Wallpaper download | `setup.rs:236–246` | soft | Already best-effort (verify timeouts) |
| 11 | Region/mirror question UX | wizard | soft | Skipped offline (see #4) |

Everything hard reduces to: **"make a local pacman repo visible wherever pacman runs,
and stop probing the network for things we don't need."**

---

## 3. Options considered

| | **A — local `file://` repo on the ISO** *(recommended)* | **B — external repo media / LAN URL** | **C — clone the live rootfs** |
|---|---|---|---|
| Idea | ISO carries `/offline-repo` (all 4 repos); mirrorlist `file://` first | Second USB stick / LAN server with the same repo, `ins arch exec --repo …` | `cp -ax / /mnt`-style install of the live system |
| UX | One USB stick, fully offline, same wizard | Two devices (or a server) — easy to lose the "install key" | One stick |
| Reuse of instantCLI | Full — same steps, same questions, same state machine | Full — same code path as A (bundle path is just a different Server base) | Poor — bypasses Disk/Config/Bootloader logic, or duplicates it |
| Fidelity to wizard options | Any option combination (bundle = union) | Any | Fixed to whatever the live profile ships (Tier-2-ish), deviates from a fresh-install layout (greetd autologin user, live config leaks) |
| Size cost | ISO +2.6–3.2 GiB (→ ~4.4–5.0 GiB) | Main ISO stays 1.81 GiB | ISO unchanged but target is a clone (large, unclean) |
| Risks | ISO size; ISO9660 placement (§4.2) | Two-media UX; still needs all the same installer changes as A | chroot identity issues (machine-id/hostname/fstab), less testable, diverges from the existing architecture |
| Verdict | **Recommended** | Sensible *extension*: Option A's installer support automatically enables B (same detection, different base path) — record as future work, not a v1 | Rejected |

All the pacman-level evidence below applies to A and B identically.

---

## 4. Recommended design (Option A) in detail

### 4.1 Bundle layout

```
/offline-repo/                                    # at ISO root (see §4.2)
├── core/os/x86_64/    {core.db -> core.db.tar.gz, *.pkg.tar.zst, *.pkg.tar.zst.sig}
├── extra/os/x86_64/   {extra.db …}
├── multilib/os/x86_64/{multilib.db …}
├── instant/os/x86_64/ {instant.db …}             # unsigned — SigLevel = Optional TrustAll
├── regions/                                      # mirror-region snapshot (§4.6 mk-region-data.sh)
│   ├── regions.html                              # raw archlinux.org/mirrorlist/ page
│   └── mirrorlists/<CODE>.txt                    # per-country lists, status-score ordered
└── packages.list                                 # manifest, consumed by verify.sh
```

- One uniform template works for all repos:
  `Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch`
  (pacman expands `$repo`/`$arch` in `Server` lines).
- Built at ISO build time: `pacman -Sw` (downloads only) against
  `releng/pacman.conf` with a scratch `--dbpath`/`--cachedir`, then per-repo
  `repo-add <repo>.db.tar.gz <pkgs…>` — **must use the `.db.tar.gz` suffix**, which is
  what creates the `core.db` symlink pacman actually requests ✅ (proven in experiments).
- `pacman -Sw` fetches `.sig` files alongside every Arch package ✅ (census in
  `test8.sh`: all Arch pkgs signed, instant pkgs unsigned). Unsigned instant packages
  install fine because `SigLevel = Optional TrustAll` travels with the `[instant]`
  section — keep it.
- **Rule: every repo enabled in the conf used at runtime must exist in the bundle**
  (core, extra, multilib, instant). multilib is always enabled by the Config step, so it
  always ships (56 packages / ~0.15 GiB).

### 4.2 Placement: ISO root, not airootfs (the 4 GiB problem)

ISO9660 (what `mkarchiso`/xorriso produce) has a **4,294,967,296-byte single-file
limit** unless multi-extent is used — and we should not bet the boot chain on it.

- Today: ISO = 1.81 GiB total; `airootfs.sfs` ≈ 1.6–1.7 GiB (rest is vmlinuz,
  initramfs, EFI/syslinux bits).
- Package archives are zstd-compressed → xz squashfs compression is essentially
  incompressible on them → bundle adds ≈ its raw size to `airootfs.sfs`.
- With the 2.4 GiB bool-union bundle: `airootfs.sfs` ≈ **4.0+ GiB → over the limit**
  (and the enum-union is bigger). Even the 2.1 GiB Tier-2 bundle would sit within
  ~500 MB of it. **Verdict: do not put the bundle in `airootfs`.**

**A1 (recommended): plain files at ISO root, injected post-build.**

```
build.sh: mkarchiso → xorriso -indev out.iso -outdev out.new \
            -boot_image any replay -map "$ISO_BUILD/offline-repo" /offline-repo -commit
          → rename
```

- Live path: archiso always mounts the boot media at `/run/archiso/bootmnt`
  (instantCLI already keys off this environment: `is_live_iso()` checks
  `/run/archiso/cowspace`, `common/distro.rs:259–261`) →
  **`/run/archiso/bootmnt/offline-repo/…`** ✅
- No recompression of 3 GiB at build time (xorriso just copies → faster builds).
- Individual files are small → 4 GiB limit never relevant; the ISO volume itself can be
  ~5 GiB.
- `verify.sh` can inspect it today: `bsdtar -tf iso | grep offline-repo`,
  `bsdtar -xOf iso offline-repo/…` for hashes.
- Requires a boot-test spike (one build + boot BIOS+UEFI) because `-boot_image any
  replay` must preserve the hybrid MBR/El Torito/GPT layout. **A1 chosen 2026-09-22
  (§10.2)**; if the spike fails, A2 cannot hold the decided full-union bundle (§10.1),
  so the fallback is a different injection method or an explicitly renegotiated scope —
  not a silent shrink.

**A2 (fallback, only if bundle scope shrinks to ≤ ~2 GiB):** put it in
`iso/overlay-offline/opt/instantos/offline-repo/` (zero build plumbing — `build.sh:38`
already merges overlays), **and** make `verify.sh` assert
`airootfs.sfs < ~3.8 GiB` so the 4 GiB limit can never be silently crossed.

### 4.3 Configuration surface (what files carry `file://`)

| Where | Change | Online-ISO behavior |
|---|---|---|
| `iso/overlay-offline/etc/pacman.d/mirrorlist` *(offline build only, merged after `overlay/`)* | `Server = file:///run/archiso/bootmnt/offline-repo/$repo/os/$arch` **first**, stock https mirrors below | N/A — online build doesn't ship the overlay; deterministic content regardless of build host (today's live mirrorlist = build host's!) |
| `releng/pacman.conf` `[instant]` (`:87–89`) | Insert the same `file://` line first, keep `https://instantos.io/packages` second. Recommended: insert conditionally in `build.sh` for the offline variant (zero risk to current builds); unconditional-with-fallback also works | fallback → https (needs the §10.6 missing-path test) |
| `INSTANT_MIRRORLIST` constant (`instantCLI/src/common/instantmirrorlist`, exposed at `common/pacman.rs:5`) | Prepend the `file://` line when a bundle is detected — opportunistic keeps https below, strict goes file://-only (used for the **target's** `[instant]`); online writes unchanged | `file://` stat fails → https fallback → unchanged behavior |
| Target `/etc/pacman.d/mirrorlist` | **No explicit change needed**: pacstrap copies the live one into the target, and the chroot bind (§4.4) makes the same absolute path resolve inside the chroot | n/a |

Fallback ordering is proven at **database level and package level** ✅ (`test7.sh`
marker-package trick, `test8.sh`): a good `file://` first wins without touching the
network; a *missing* file with a working https second is healed online; a missing file
with a dead https second fails loudly — exactly the semantics we want offline
(completeness is guaranteed at build time by `verify.sh`).

### 4.4 Runtime paths: live → chroot → target

```
live:   file:///run/archiso/bootmnt/offline-repo/…          (shipped mirrorlist)
chroot: same absolute path, via
        mount --bind /run/archiso/bootmnt /mnt/run/archiso/bootmnt
target: mirrorlist/pacman.conf are byte-identical to live's (inherited) → zero
        rewriting needed DURING the install; cleanup rewrites at the END (§4.5.11)
```

`arch-chroot` only binds `/dev, /proc, /sys, /run` — it does **not** pick up arbitrary
host paths; the experiments had to `mount --bind` manually before any in-chroot pacman
transaction worked ✅ (`test9.sh`, `test10.sh`).

Binding `bootmnt` (rather than a synthetic `/opt/instantos` path) is what keeps the
design idempotent: live config, target config, and scripts all use one path.

### 4.5 instantCLI change list (implemented 2026-09-22, Phase 1)

1. **New `src/arch/offline.rs`** — single source of truth. A `Mode` enum
   (`Online` / `Opportunistic` / `Strict`) rather than a bool, so strict-mode
   differences (file://-only lists) are first-class:
   ```rust
   pub fn resolve(env_forced: bool, bundle_present: bool) -> Mode {
       match (env_forced, bundle_present) {
           (true, _)   => Mode::Strict,           // INS_OFFLINE=1
           (false, true) => Mode::Opportunistic,  // probe: …/offline-repo/core/os/x86_64/core.db
           (false, false) => Mode::Online,
       }
   }
   pub fn mode() -> Mode                        // env read + one stat
   pub fn validate(mode) -> Result<()>          // strict without bundle bails fast
   ```
   System-touching helpers (`bind_bundle`, `copy_dotfiles_snapshot`,
   `cleanup_target`, mirrorlist shaping) take an explicit `Mode` parameter so
   tests inject the mode without env or filesystem setup. Detection also runs
   inside the chroot, where the bind from #6 makes the probe resolve to the
   same bundle.
2. **`cli/commands/install.rs:89`** — `ensure_interactive_internet()` relaxed,
   not skipped (per §10.8): offline keeps the nmtui loop but the reject action
   becomes *Continue without network* instead of *Abort installation*.
3. **`cli/commands/ask.rs`** — `ensure_internet(system_info, mode)` takes the
   mode explicitly; offline returns `Ok` before the connectivity check; tests
   at `ask.rs:363+` extended with offline pass-through cases. The wizard also
   calls `offline::validate()` here, and `print_system_checks` prints an
   `Install Source:` line.
4. **`mirrors.rs:294` (`MirrorlistProvider`)** — when offline, read the bundled
   region snapshot (`offline-repo/regions/`) instead of fetching: the raw
   `regions.html` goes through the *same* parser as the live page
   (`parse_region_options`, extracted from the fetch path), then
   `MirrorRegionsKey`/`MirrorRegionCodesKey` are populated with
   `MirrorRegionsFetchFailed = false` → **the region question is asked
   offline** (§10.11). No archlinux.org traffic, no probing. Without a
   snapshot (old/partial bundle) it degrades exactly like a failed fetch
   (`MirrorRegionsKey = []` + `FetchFailed = true`) → question hidden,
   fallback list — the pre-§10.11 behavior.
5. **`execution/base.rs setup_mirrors`** — three-way `MirrorlistAction`:
   `Fetch` (unchanged online path), `Keep` (opportunistic: never fetches —
   avoids the latency-probe fallback chain at `mirrors.rs:247` — but now
   *writes* `file://` + the selected region's bundled list over the shipped
   mirrorlist, so pacstrap and the target inherit a region-tuned list; with no
   resolvable region the shipped `file://`-first list is kept as-is),
   `Replace` (strict: write the `file://`-only list so no network attempt is
   even configured). `pacstrap` then just works through the `file://`-first
   mirrorlist ✅.
6. **`execution/mod.rs setup_chroot`** — now calls `offline::bind_bundle()` +
   `offline::copy_dotfiles_snapshot()`:
   - `findmnt`-guarded `mount --bind /run/archiso/bootmnt /mnt/run/archiso/bootmnt`
     (idempotent — `setup_chroot` runs once per chroot step and must not stack
     binds), dry-run aware,
   - exists-guarded `cp -a` of `/usr/share/instantos/build-inputs/dotfiles`
     into the target (the chroot cannot see live airootfs paths otherwise;
     the snapshot is a real git repo, a few MB, already shipped by
     `build.sh:80–86`).
   Bind teardown happens in the finish-time cleanup (#11); `/mnt` itself is
   never unmounted on any success path (only the btrfs error path at
   `filesystem.rs:69` umounts, pre-bind), so no ordering hazard exists at the
   existing sites.
7. **`common/pacman.rs setup_instant_repo(dry_run, offline_content)`** —
   signature now carries the mirrorlist content; callers pass
   `offline::instant_mirrorlist_override()`: `None` online (a user-authored
   list is never overwritten), opportunistic prepends the `file://` line above
   the https instant mirrors, strict writes `file://`-only. The `[instant]`
   section append is unchanged; the mirrorlist is (re)written when the section
   is new, the file is missing, or offline content is supplied.
   `setup.rs:158 pacman -Sy` then syncs `[instant]` from the bundle inside the
   chroot ✅ (mechanism proven in `test9/test10` with the experiment's
   `/opt/...` path; the real path only differs by the bind target).
8. **`execution/setup.rs setup_user_dotfiles`** — offline clones
   `/usr/share/instantos/build-inputs/dotfiles` through a new flag:
   `ins dot repo clone <local-path> --origin <github-url>`.
   `clone_repository` clones from the local path, then
   `common::git::set_remote_url` rewrites git's origin **and** the URL stored
   in `dots.toml` to the canonical https URL, so a later online
   `ins dot update` behaves normally. Local-path cloning itself was already
   supported (`dot/git/repo_ops.rs:71–80` canonicalizes existing paths and
   disables shallow clone; `resolve_repo_name` reads the snapshot's metadata
   or falls back to the basename → `dotfiles`) — §10.3 verified by code
   inspection.
9. **`ask.rs:146` live deps** — no code change: works once the live mirrorlist is
   `file://`-first and the bundle contains **`gum` + `ntfs-3g`** (add them explicitly to
   the package list; the rest of the deps are already on the live ISO, §1.1).
10. **Soft downloads** — geo provider stores the empty `GeoLocation` offline (no
    public-IP disclosure; identical fallback to a failed lookup). Wallpaper
    download is skipped outright offline instead of relying on per-source
    timeouts.
11. **Install finish — target cleanup** (`offline::cleanup_target`; runs on the
    full-install path always, no-ops online):
    - strip `file://` `Server` lines from the target's `mirrorlist`,
      `instantmirrorlist`, and `pacman.conf`,
    - restore a network list when stripping would leave a mirrorlist without a
      single server (strict installs): **the selected region's bundled list**
      for `/etc/pacman.d/mirrorlist` (falling back to `geo.mirror.pkgbuild.com`
      when no region/snapshot resolves), `INSTANT_MIRRORLIST` for
      `instantmirrorlist`, nothing for `pacman.conf` (a stripped network block
      is its intended end state);
    - umount the bind (warning-only on failure — the install already succeeded),
    - asserted e2e in Phase 3: `grep -r 'file://' /mnt/etc/pacman` is empty.
    Result: the installed system is byte-equivalent to one installed online.
12. **pacman/pacstrap retry loops** (`execution/pacman.rs`) — offline retries
    skip reflector/shuffle/mirror re-sync (they cannot help) with a 1 s backoff
    and bail with a bundle-specific message instead of "check your internet
    connection".

### 4.6 ISO build changes (`instantOS`)

**Package-list generation (`iso/offline/mk-package-list.sh`, output committed as
`iso/offline/packages.list`):**

- Oracle: `ins arch exec --dry-run -f <questions>` (already proven: full-profile run =
  888 packages, `dryrun-full.txt` ✅).
- The union must cover **every wizard path**, not just booleans: generate one questions
  file per variant of the enums in `install_plan.rs:446–464`
  (`Kernel`, `DesktopEnvironment`, `DisplayManager`, plymouth/xorg/minimal flags …),
  dry-run each, union the outputs; then add:
  - hardware-conditional packages (e.g. `blueman` when `system_info.has_bluetooth`,
    `setup.rs:173–176`),
  - live runtime deps (`gum`, `ntfs-3g`),
  - anything else gated on `system_info` found by grep during implementation.
- `verify.sh` fails the build if any package in `packages.list` is unreachable from the
  bundle → staleness is caught mechanically.

**`build.sh --offline` (new flag, offline variant only):**

1. `mk-package-list.sh` → `packages.list`.
2. `pacman --config releng/pacman.conf --dbpath <scratch> --cachedir <cache> \
   -Sw --noconfirm $(cat packages.list)` (build host has network; `[instant]` already
   in `releng/pacman.conf:87`).
3. Stage `core|extra|multilib|instant/os/x86_64/…` + `repo-add *.db.tar.gz …`;
   copy `packages.list` in as manifest; run
   `offline/mk-region-data.sh $ISO_BUILD/offline-repo/regions` (written +
   run-verified 2026-09-22; needs `jq`, added to the Docker build deps — the
   per-country endpoint 429-rate-limits a region loop, so the script makes two
   requests: raw `mirrorlist/` page + mirror-status API) →
   `$ISO_BUILD/offline-repo/`.
4. `sed` the `file://` line into the build profile's `releng/pacman.conf [instant]`;
   copy `iso/overlay-offline/…` over `instantlive/airootfs/` (same merge as `build.sh:38`).
5. `mkarchiso` unchanged.
6. xorriso injection (A1, §4.2); name the artifact `…-offline.iso`.
7. `verify.sh` (below).

**`verify.sh` additions (offline variant):**

- `bsdtar -tf` → assert `/offline-repo/{core,extra,multilib,instant}/os/x86_64` and
  every entry of `packages.list` present; `$repo.db` present; `.sig` present for all
  non-instant packages; instant section keeps `SigLevel = Optional TrustAll`;
  `/offline-repo/regions/regions.html` and ≥1 `regions/mirrorlists/*.txt` present.
- Assert **every file in the ISO (incl. `airootfs.sfs`) < 4 GiB − margin**.
- Assert the live image ships the `file://`-first mirrorlist
  (`image_cat etc/pacman.d/mirrorlist | grep file://`).
- Existing checks unchanged.

**Workflow / tooling:**

- `.github/workflows/iso.yml`: build both variants (matrix) but **publish split** —
  the online ISO + checksums as GitHub release assets (must stay **< 2 GiB**;
  today 1.81 GiB with ~200 MB headroom, so also track live-system growth), and the
  offline ISO to **SourceForge** (§10.9 — the workflow can no longer
  `gh release upload` that asset; Phase 4 needs a SourceForge project account/API
  credential or a manual upload step).
  Both checksums and both links appear on the GitHub release.
- `justfile`: `build-iso-offline` target next to `build-iso`.
- **Acceptance test = e2e with no NIC.** The e2e harness records `NICTYPE=user`
  (`instantOS-e2e/docs/FINDINGS.md:55`, `vars.json`) — add/confirm `NICTYPE=none`
  (qemu `-nic none`) and run the full install from the offline ISO: installer reaches
  `Finished`, installed system boots, cleanup assertion (§4.5.11) passes.
  The online path keeps its existing `just test` / e2e coverage.

---

## 5. Evidence (what was actually proven)

All runs in Docker (`archlinux:base-devel`); test repo bundle ~361 MiB at `/work/repo`;
scripts in `/tmp/opencode/offline-exp/`.

| Claim | Result | Script |
|---|---|---|
| `pacstrap` from a `file://` repo with network fully disabled (172–180 pkgs) | ✅ PASS | `test.sh` (Phase B) |
| instantCLI drives pacstrap without `-C` → **target inherits the live mirrorlist** (the leverage point) | ✅ PASS | `test2.sh` (Phase B2) |
| Full chain offline: `pacstrap` → in-chroot `pacman -Sy` → `pacman -S` from the bundle (after removing the container's `NoExtract` image artifact) | ✅ PASS | `test4.sh` (Phase B3) |
| Server ordering, decisive: marker package proves the **db** came from `file://` when present and from https when absent; **package-level** gap healed from mirror online (C4a) | ✅ PASS | `test7.sh` (Phase C3) |
| Bundle **gap + dead fallback = fatal** (loud failure, no silent wrong install) | ✅ PASS | `test7.sh` C4b, `test8.sh` C4b (corrected: `fzf` removed first) |
| **Same-size tampering** in the bundle is rejected by checksum/PGP (offline is as trustworthy as online) | ✅ PASS | `test7.sh` C3, `test8.sh` C3 |
| Signature census: all Arch packages have `.sig`; instant packages unsigned → `Optional TrustAll` required | ✅ measured | `test8.sh` |
| Full design at a fixed path: bundle bind-mounted into `/mnt`, driving pacstrap **and** every in-chroot transaction | ✅ PASS | `test9.sh` (Phase D) |
| Negative control: package not in the bundle fails (`pacman -S htop` → "not found") | ✅ PASS | `test9.sh:52` |
| In-chroot `pacman -S` install from bundle (workaround: container overlayfs `CheckSpace` artifact) | ✅ PASS | `test10.sh` (Phase D2) |
| Fallback-chain variants (ordering, local-mirrorlist fallback, working-mirror reruns) | ✅ superseded by test7/8 | `test3.sh`, `test5.sh`, `test6.sh` |
| Sizing tiers from the real `ins` package plan | ✅ measured (§6) | `measure.sh`…`measure5.sh`, `dryrun-full.txt` |
| Fixtures: offline-only and file→https fallback configs | — | `pacman.offline.conf`, `pacman.fallback.conf` |

**Container artifacts — do not mistake for real-world behavior:**
`NoExtract = etc/pacman.conf` (Docker image only, removed in `test4.sh`);
overlayfs `CheckSpace` / "could not determine cachedir mount point"
(disabled `#CheckSpace` in-chroot; real install targets are btrfs/ext4 → fine);
`mirror.osbeck.com` 404s (use `https://fastly.mirror.pkgbuild.com/$repo/os/$arch`);
firefox `.part` rename races on an overlayfs cachedir with parallel downloads
(`measure5.log`).

---

## 6. Sizing

| Tier | Packages | Download size | Notes |
|---|---|---|---|
| 1 — TTY base profile | 762 | 1.2 GiB | no GUI |
| 2 — wizard default (instantWM + GDM + btrfs + full `linux-firmware`) | 824 | 2.1 GiB | close to what a default user installs online (e2e measured **1.57 GiB downloaded** for its fixture — `instantOS-e2e/docs/FINDINGS.md`) |
| 3 — union of all **boolean** options | 888 (core 198 / extra 604 / multilib 56 / instant 30) | 2.4 GiB | bool-union only — enums take one merged value |
| 4 — **enum-union** (alt kernels/DMs/DEs + hw-conditional + `gum`/`ntfs-3g`) | est. ~950–1050 | **est. 2.6–3.2 GiB** | compute exactly via `mk-package-list.sh` (§4.6) |

ISO projections (A1 placement — plain files, no recompression):

| Artifact | Size |
|---|---|
| Online ISO (today, unchanged) | 1.81 GiB |
| Offline ISO, Tier-3 bundle | ~1.81 + 2.4 ≈ **4.2 GiB** |
| Offline ISO, full enum-union bundle (**decided scope**, §10.1) | **4.4–5.0 GiB** |

Notes: the bundle duplicates packages whose *contents* are already installed in
airootfs — accepted trade-off (installed files ≠ package archives; pacstrap/pacman need
the archives + dbs). The full-option union costs only ~0.3 GiB over the default profile,
so a "full-union" bundle is cheap relative to the wizard fidelity it buys.

---

## 7. Gotchas (consolidated)

1. **ISO9660 4 GiB single-file limit** → bundle outside `airootfs` (§4.2). Any
   future change that reconsiders this must re-run the size math *and* assert in
   `verify.sh`.
2. **`arch-chroot` binds only `/dev /proc /sys /run`** → explicit
   `mount --bind … /mnt/run/archiso/bootmnt` is mandatory (`test9/test10` needed it ✅);
   cleanup must umount it **before** `/mnt` (or use `umount -R`), and also on failure
   paths (`disk/filesystem.rs:69`).
3. **Every enabled repo must be bundled or disabled** — a missing repo (even with zero
   needed packages from it) fails the whole `pacman -Sy`. multilib is always enabled by
   the Config step → always bundle it.
4. **`repo-add` needs the `*.db.tar.gz` name** → creates the `core.db` symlink pacman
   requests ✅.
5. **Instant packages are unsigned** → keep `SigLevel = Optional TrustAll`; Arch
   packages need their `.sig` files copied (pacman downloads them ✅ census in
   `test8.sh`).
6. **Integrity holds offline** — same-size tampering rejected ✅ (`test7/test8`); no
   downgrade in trust vs online.
7. **Target inherits the live mirrorlist** (no `-C`/`-P`) — that's the leverage point,
   and also the reason the installed system must be **cleaned up** afterwards
   (§4.5.11) or it keeps `file:///run/archiso/...` references forever.
8. **`setup_mirrors` overwrites the live mirrorlist** during Base
   (`base.rs:52`) — the offline path must *skip* the fetch, not race it.
9. **The mirror fallback chain probes latency even for a local file**
   (`mirrors.rs:247`) — "just put a local mirror last" does **not** work offline;
   the offline path must bypass the chain.
10. **Build-time pacman sees `file://` lines before the bundle exists** (mkarchiso
    chroot has no `/run/archiso`) → the https second entry must fall back cleanly;
    required test in Phase 0 (§10.6), applies to `releng/pacman.conf [instant]` and the
    target `instantmirrorlist` on online installs.
11. **Live ISO lacks `gum` and `ntfs-3g`** → runtime `pacman -S` on the live system
    needs them in the bundle (`ask.rs:146–179`).
12. **`file://` first changes live behavior subtly**: a *live* (never-offline) session
    prefers bundled (release-frozen) versions over mirror updates. Acceptable —
    bundle == release; document it.
13. **Exotic boots** (ventoy/netboot/HTTP) may not expose the bundle → detection
    (`/run/archiso/bootmnt/offline-repo/core/...` probe) fails → gracefully back to
    today's online behavior. Never hard-require the bundle.
14. **Container artifacts** (§5) vs real Arch — already triaged; keep the list in mind
    when reproducing.
15. **`ins` flags changed** — `--trust-config` no longer exists; use
    `ins arch exec --dry-run -f …` as the package-plan oracle ✅.
16. `repo-add`/bundle on overlayfs cachedirs had `.part` rename races with parallel
    downloads (`measure5.log`) — on a real build host use a normal filesystem
    cachedir or `--disable-download-timeout`/serial downloads if it recurs.
17. **GitHub release assets are capped at 2 GiB per file.** The current ISO
    (1,938,161,664 B) fits with ~200 MB to spare; the offline ISO (~4.4–5.0 GiB)
    never can → external hosting (§10.9), and keep an eye on online-ISO growth
    against the same limit. Splitting the ISO into <2 GiB parts to stay on GitHub
    is possible but rejected as needlessly hacky UX.

---

## 8. Implementation plan (ordered)

**Phase 0 — spikes (½ day)** — product decisions are locked (§10: full enum-union,
A1 *provisional on the spike below*, opportunistic, both artifacts, SourceForge):
- ~~Decide bundle scope and placement~~ — decided 2026-09-22 (§10.1 scope, §10.2
  placement); if the spike below fails, A2 can't hold the full-union bundle →
  renegotiate scope or find another injection method (§10.2).
- Spike: xorriso `-boot_image any replay -map` on a built ISO → boot it BIOS+UEFI.
- Test: `file://` path *missing entirely* first + https second, db- and package-level
  (§10.6) — this unblocks the unconditional-with-fallback config choice.
- Confirm `gum`'s repo and `pacman -Si` availability for the bundle list (§10.5).

**Phase 1 — instantCLI — DONE 2026-09-22** (`cargo check`, `cargo test` 1256 green
incl. 20 offline tests, `cargo fmt --check`, `cargo clippy` — 6 warnings, all
pre-existing in untouched files):
- `arch/offline.rs`: `Mode` detection + strict validation + mirrorlist shaping +
  bind/snapshot/cleanup, `Mode`-parameterized for injection in tests.
- Gates (#2, #3), mirror provider bundled-snapshot load (#4), `setup_mirrors`
  actions (#5),
  `setup_chroot` bind + snapshot copy (#6), mode-aware `instantmirrorlist` (#7),
  dotfiles `--origin` clone (#8), finish-time cleanup (#11), geo/wallpaper
  skips (#10), offline-aware pacman/pacstrap retry loops.
- MockRunner tests assert `findmnt`/`mkdir`/`mount --bind`/`umount` recorded
  offline and absent online; `ask.rs` internet tests extended; fmt/clippy per AGENTS.

**Phase 2 — ISO build (`instantOS`) — DONE 2026-09-23**
- `iso/offline/mk-region-data.sh` — DONE 2026-09-22 (writes `regions.html` +
  74 `mirrorlists/*.txt`, ~310 KB, 0.8 s; run-verified; two-request design after
  the per-country loop hit HTTP 429).
- `iso/offline/mk-package-list.sh` + committed `packages.list` — DONE
  2026-09-23: 81 distinct plan variants (kernel × GPU, DE × DM × xorg,
  plymouth × minimal, filesystem × encryption, 16 locales, UEFI/CPU/
  bluetooth/NIC-firmware/VM-guest-tools conditionals; tty installs omit the
  DM/xorg answers, encrypted installs carry the password) dry-run via
  `ins arch exec --dry-run`, unioned with the live runtime deps
  (`gum`, `ntfs-3g`). Result: 107 explicit packages; the download closure
  (~900+ archives, the §6 estimate) is expanded by `pacman -Sw` at bundle
  time. Falls back to the committed list when no `ins` binary is available.
- `iso/offline/mk-bundle.sh` — DONE 2026-09-23: scratch pacman conf
  (releng's repos + multilib enabled + scratch mirrorlist + DisableSandbox
  for containers), `-Sy` + `-Sw` the closure, stage per-repo by first-repo
  resolution, `repo-add *.db.tar.gz`, fail on any manifest gap, region
  snapshot, manifest shipped in the bundle.
- `build.sh --offline` — DONE 2026-09-23: overlay-offline merge (file://-
  first mirrorlist), `file://` sed into the profile's pacman.conf `[instant]`,
  bundle build before mkarchiso, xorriso `-boot_image any replay -map`
  injection, `instantos-<ver>-offline.iso` naming, verify with `--offline`.
- `verify.sh --offline` — DONE 2026-09-23: repo dbs, manifest ⊆ staged
  packages (exact pkgname match via `.PKGINFO`-style suffix strip), `.sig`
  presence for signed repos, regions snapshot, 4 GiB single-file margin,
  file://-first mirrorlist + `[instant]` bundle server in the airootfs.
- `just build-iso-offline` (+ `-docker`/`-native`) — DONE 2026-09-23.
- Pending within the release chain: the Phase 0 xorriso boot spike (BIOS+UEFI
  boot test of an injected ISO) — still to run before calling the artifact
  production-ready.

**Phase 3 — end-to-end proof**
- e2e: `NICTYPE=none` run against the offline ISO; full install → boot installed OS;
  assert no `file://` remnants (`grep -r file:// /etc/pacman`).
- Region question asked offline: no answers-file change needed — all three e2e
  question files already carry `MirrorRegion = "Germany"` (verified 2026-09-22).
- Regression: existing online e2e (`just test` in instantCLI, instantOS-e2e suite)
  must pass **unchanged** — proves the online path is untouched.

**Phase 4 — release**
- `iso.yml` matrix (online/offline): online ISO + checksums as GitHub release assets
  (must stay < 2 GiB), offline ISO → **SourceForge** (needs a project account/API
  credential or a manual upload step), cross-links on the GitHub release; README/docs
  note about size (~4.4–5 GiB) and the offline guarantee.

**Acceptance criteria:** offline ISO installs a bootable system in a VM with *no NIC
attached*; installed system has no `file://` pacman references; online ISO behavior and
size unchanged.

---

## 9. What "done" looks like

- `just build-iso-offline` → `instantos-<ver>-offline.iso` (~4.4–5 GiB), `verify.sh`
  green, uploaded to SourceForge; the GitHub release carries the online ISO, both
  checksums, and the offline ISO link.
- e2e with `NICTYPE=none`: wizard → install → reboot → login, zero network.
- `grep -R "file://" /etc/pacman.d /etc/pacman.conf` on the installed system: empty.
- Online artifact: same size class (1.81 GiB), same gates, same tests.

---

## 10. Decisions & verifications

Product decisions were made on 2026-09-22; items marked *(verification)* are
tests run during Phase 0 / implementation — no further decisions needed.

**Resolved decisions:**

1. **Bundle scope = full enum-union** (~2.6–3.2 GiB → ISO ~4.4–5.0 GiB). Every wizard
   path — all kernels, desktops, display managers, all boolean options,
   hardware-conditional and live runtime deps — must install offline;
   `mk-package-list.sh` computes the exact list (§4.6).
2. **Placement = A1** — plain files at ISO root, xorriso `-boot_image any replay -map`
   injection (§4.2). Chosen provisional on the boot spike: if the spike fails, A2
   cannot hold the full-union bundle (§10.1), so the fallback is a different injection
   method or an explicitly renegotiated scope — not a silent shrink.
3. ~~*(verification)* **`ins dot repo clone <local-path>`**~~ — verified 2026-09-22 by
   code inspection: `repo_ops.rs:71–80` canonicalizes existing paths and disables
   shallow clone, `resolve_repo_name` falls back to the basename (`dotfiles`).
   Implemented with a new `--origin <url>` flag that rewrites git's origin and
   the stored `dots.toml` URL after a local clone (§4.5.8).
4. *(verification)* **Does pacstrap `-C` propagate `pacman.conf` into airootfs?**
   Determines whether the live `[instant]` section exists at runtime (nothing critical
   rides on it — no live dep comes from `[instant]` — but confirm).
5. *(verification)* **`gum`'s repository** (extra vs instant) — affects the bundle list
   and live-dep resolution.
6. *(verification)* **Missing-`file://`-path-first fallback** test (db + package level)
   — expected to pass (pacman iterates servers on error) but must be proven; it
   underwrites the opportunistic "`file://` first, https fallback" shape (the live
   mirrorlist shipped by the offline build, and the target's list during install).
7. **Option B (external repo media)** — settled as future work, not v1: it falls out of
   A for free (same detection, different base path); `bundle_root()` stays pluggable.
8. **Offline semantics = opportunistic** — bundle first; a present network heals gaps;
   internet gates relaxed but `nmtui` still offered; `INS_OFFLINE=1` forces strict
   networkless mode for tests. With no network — the target scenario — opportunistic
   and strict behave identically.
9. **Hosting = SourceForge**, and **release shape = both artifacts**. External hosting
   is required at all because GitHub caps each release asset at 2 GiB: the current
   online ISO sits at 1.81 GiB (~200 MB headroom) and no bundle tier fits under the
   remainder. GitHub releases keep the online ISO + both checksums + the link to the
   SourceForge-hosted offline ISO (§7.17). Torrent listed as an optional supplement.
10. **Live-session staleness accepted** (gotcha 12): the offline live session prefers
    release-frozen bundled packages; documented rather than coded around — the
    alternative (prepending `file://` only at install time) adds code for no real user
    benefit.
11. **Bundled mirror-region data; region question asked offline** (2026-09-22, user
    proposal, approved same day) — the bundle carries `regions/` (~310 KB: raw
    `mirrorlist/` page + per-country lists composed from the mirror-status API,
    status-score ordered). Offline the wizard asks the region question from disk
    (same machinery, `FetchFailed = false`); opportunistic installs write
    `file://` + the region list, strict restores the region list at cleanup —
    parity with online installs (§4.5.4/5/11). Missing snapshot degrades to the
    old skip. Per-country endpoint loop abandoned after HTTP 429: two requests
    instead of 79.

**Accepted technical defaults** (taken unless revisited): the offline build `sed`s the
`file://` line into `releng/pacman.conf` so the online build stays byte-identical;
`INSTANT_MIRRORLIST` is written mode-aware — online installs keep today's
byte-identical network-only list (one `ins` binary serves both ISOs, and no
`file://` line ever exists to leak), offline installs get `file://`-first with
https fallback (strict: file://-only), and any `file://` lines are stripped from
the target at install finish;
artifact name `instantos-<ver>-offline.iso`; `INS_OFFLINE=1` env override ships
(strict: fails fast if no bundle is present).

---

## Appendix A — experiment artifacts

| Path | Contents |
|---|---|
| `/tmp/opencode/offline-exp/test{,2,3,4,5,6,7,8,9,10}.sh` | Phases B→D2 per §5 (headers state phase + intent) |
| `/tmp/opencode/offline-exp/measure{,2,3,4,5}.sh`, `measure5.log`, `dryrun-full.txt`, `urls.txt`, `plan.txt`, `prep.sh` | Sizing + package-plan oracle runs |
| `/tmp/opencode/offline-exp/pacman.offline.conf`, `pacman.fallback.conf` | Minimal conf fixtures (file-only / file+https) |
| `/tmp/opencode/offline-exp/repo/` | 361 MiB test bundle (`core` subset + `instant`), `repo-add`-built |
| Docker: image `arch-offline:prep`, container `ins-prep` (`/work/repo`, `/work/bundle-cache`) | Reproducible environment |

## Appendix B — key file:line index

`instantCLI`: `cli/commands/install.rs:40,89` (internet gate) ·
`cli/commands/ask.rs:138,146,321,363` (gate, live deps, tests) ·
`mirrors.rs:54,128,247,294` (region fetch, fallback chain, probing, provider) ·
`execution/base.rs:8,21,52,148` (Base step, mirror overwrite, pacstrap) ·
`execution/pacman.rs:155` (pacstrap wrapper) ·
`execution/mod.rs:588,684,756` (chroot re-invocation, setup_chroot, MockRunner) ·
`execution/setup.rs:11,150,158,187,205,236` (dotfiles const, instant repo, -Sy, clone, wallpaper) ·
`common/pacman.rs:5,12,52` (INSTANT_MIRRORLIST, setup_instant_repo, multilib) ·
`common/distro.rs:259` (is_live_iso → `/run/archiso`) ·
`engine/install_plan.rs:446` (InstallPlan fields) ·
`execution/disk/filesystem.rs:69`, `disks.rs:181` (umount `/mnt`).

`instantOS/iso`: `build.sh:36,38,49,86,118,129` (overlay merge, source fetch, dotfiles
snapshot, mkarchiso, verify) · `releng/pacman.conf:87` (`[instant]`) ·
`releng/profiledef.sh:14` (xz squashfs) · `releng/packages.x86_64` (live deps;
missing `gum`, `ntfs-3g`) · `verify.sh` (bsdtar/unsquashfs assertions) ·
`.github/workflows/iso.yml`, `justfile` (release flow).
