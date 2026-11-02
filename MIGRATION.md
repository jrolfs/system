# Migration: homeshick + channels → flakes + home-manager

Durable record of the migration this repo is undergoing. (The Claude Code
plan files under `~/.claude/plans/` are ephemeral; this file is the source
of truth.)

## Goal

Collapse four homeshick castles (`macos`, `dot`, `neovim`, `private`) plus a
channels-based nix-darwin config into **one flake** that configures every
machine — macOS and the NixOS NUC — from a single source, with home-manager
owning the dotfiles.

## Architecture

- **One repo.** This repo (`main`; deploys to `~/.config/system` on a
  machine). The pre-flake channels-and-homeshick configuration is kept on the
  `pre-flake` branch. `flake.nix` exposes:
  - `darwinConfigurations.ala` — new MacBook (phase 1 target)
  - `darwinConfigurations.newt` — daily driver (phase 3, added last)
  - `nixosConfigurations.irulan` — Beelink NUC home server (phase 2)
- **`dot` subtree-merged** into `dotfiles/` with full history. The old `macos`
  castle's `home/` was consolidated in beside it. `modules/home/*` symlinks the
  tree into `$HOME` (lift-and-shift by default; `programs.git`/`direnv`/
  `starship`/`atuin` translated where it paid off; `zed`/`karabiner`/`vscode`/
  `cursor` via `mkOutOfStoreSymlink` so the apps can write back).
- **`neovim`** stays its own repo, but the config is edited from a clone at
  `~/Developer/Sources/jrolfs/neovim`, not from the pinned input. `modules/home/
  neovim.nix` owns all of `~/.config/nvim`: it links each *top-level* entry of
  the config to the clone via `mkOutOfStoreSymlink`, clones the repo on
  activation if it isn't there, and warms the plugin set. So a lua tweak is
  live, and `inputs.neovim-config` (`flake = false`) is down to supplying the
  list of top-level names — an absolute path can't be read under pure eval —
  which makes a new top-level entry the one change still needing
  `nix flake update neovim-config`.
- **The desktop** is split between the two places macOS keeps it.
  `modules/darwin/defaults.nix` has the parts that are preferences: widgets off
  (`WindowManager.Standard/StageManagerHideWidgets`), which volumes get an icon,
  and the desktop's own icon-view options as a
  `CustomUserPreferences."com.apple.finder".DesktopViewSettings` dictionary —
  nix-darwin has no structured option for that one because it's a nested dict,
  not a flat key. The picture itself is `modules/home/wallpaper.nix`, because it
  isn't a preference at all: see the gotcha below.
- **`private`** stays a homeshick castle (git-crypt). `$HOMESHICK_KINGDOM` is
  still exported so `OP_CONFIG_DIR` etc. resolve. bootstrap clones, links,
  pulls *and* — since `castle-unlocked` — unlocks it; before that phase existed
  a provisioned machine got the castle as ciphertext, `keys.zsh` included. Two
  places in `modules/home/default.nix` exist for it: `liveConfig "zsh"` and
  `git` with `recursive = true`, both so homeshick can plant a file inside a
  directory home-manager also manages.
- **Submodules dropped.** nix-darwin / nixpkgs are flake inputs pinned to
  upstream; the custom Homebrew tap lives in-repo as plain files (`homebrew/`).

### Layout

```
flake.nix / flake.lock
hosts/{ala,newt,irulan}/default.nix    # per-host
modules/darwin/                        # nix-darwin modules (was home/.nixpkgs/)
modules/nixos/{default.nix,services/}  # NixOS (Irulan)
modules/home/{default,darwin,linux}.nix + hosts/<host>.nix
overlays/{default.nix,pin.nix}         # overlay + pin helper
homebrew/                              # dehydrated tap (plain files)
dotfiles/home/…                        # the merged dotfile tree
icons/                                 # custom app-icon assets + apply.sh
MIGRATION.md
```

## Key conventions / gotchas

- **`builtins.getEnv` returns `""` under pure flake eval.** Replaced everywhere:
  `icons.nix`/`spicetify.nix` derive `xdgDataHome` from `specialArgs.userName`;
  `homebrew.nix` uses a per-host `excludeByHost` attrset keyed on `hostname`.
- **`builtins.currentTime` is unavailable under pure flake eval** (channels
  allowed it). `overlays/pin.nix` dropped its `day`-bucket; the cache-probe
  derivation is named `cache-status-${hash}` so it re-runs when the pinned
  package's current build changes — the right time to re-check anyway.
- **`nix.package = pkgs.lixPackageSets.lix_2_94.lix`** — Lix 2.95 dropped
  `builtins.fetchClosure`, which devbox needs. Revert to `pkgs.lix` (2.95.2)
  once nothing uses devbox. Converted: `bootstrap` (`use flake` against its own
  `devShells.default`) and `.config/glide` (`use flake .#glide` against this
  repo's). Still on devbox:
  `jrolfs/{website,gruvbox-material-firefox,gruvbox-material-tridactyl}` and
  the Hover repos that the private-castle prune will take out. Every one of
  those `devbox.json`s is `devbox init` boilerplate plus a package list, so
  they're ~12-line devShells when the time comes. `pkgs.devenv` is installed
  but unused — no `devenv.nix` in any of Jamie's own repos.
- **Nested flakes aren't worth it in this repo.** Nix resolves a `flake.nix` in
  a subdirectory to `git+file://…?dir=<subdir>`, so the entire repo is copied
  to the store regardless — and the subdirectory's files have to be
  git-tracked. A `devShells.<name>` on the root flake plus `use flake .#<name>`
  in the subdirectory's `.envrc` costs the same copy without a second
  `flake.lock` or a second nixpkgs. Nix searches up from a directory with no
  `flake.nix`, so the relative ref just works — including through the
  `mkOutOfStoreSymlink` indirection. Caveat: entering such a shell realizes
  *all* of the root flake's inputs, so first entry fetches the theme repos too.
- **`tap.nix`** cask-updater writes to the working tree → uses `$NIX_CONFIG_DIR`
  (set via `home.sessionVariables`), never `${self}` (read-only store path).
- **icon-customizer FDA**: `/usr/local/bin/icon-customizer` is a stable-path
  Mach-O wrapper so the Full Disk Access grant survives rebuilds. Sudoers rule
  for `icon-setter` is now declared via `environment.etc` (nix-darwin keeps it
  in lockstep with the store path). Grant FDA once after the first switch.
- **The wallpaper is not a preference.** macOS 26 keeps the desktop picture and
  the screen saver together in `~/Library/Application Support/
  com.apple.wallpaper/Store/Index.plist`, and `WallpaperAgent` *owns* that file
  rather than reading it. Measured: writing the new picture into it changes
  nothing on screen, and the agent overwrites the file from its own state the
  next time Dock restarts — so `CustomUserPreferences` is not a route, and
  neither is any amount of plist surgery. The only public way in is
  `NSWorkspace.setDesktopImageURL`, so the work lives in Hammerspoon, which is
  where this config keeps the macOS APIs that have no declarative surface:
  `dotfiles/home/.hammerspoon/modules/wallpaper.lua` does it through
  `hs.screen:desktopImageURL`, and `modules/home/wallpaper.nix` declares the
  path and calls into it from activation. Four consequences worth knowing:
  - It reaches the **active space only**, and the other spaces are reached *on
    arrival*, not by a switch going and getting them. System Settings writes an
    "all spaces and displays" scope no public API touches, and the only way to
    paint a space you aren't on is `hs.spaces.gotoSpace`, which works by
    driving the Mission Control UI — it takes the screen for about a second a
    space, and keystrokes during the hop land wherever it went. That is not
    something a `nix-switch` should do to you unasked, so activation paints the
    space you are on and leaves an `hs.spaces.watcher` armed to catch the rest
    as you visit them. `M.walk()` is the impatient version, by hand. Either way
    it does nothing at all unless the declared picture changed: the guard reads
    the URL back off every attached screen, 16ms. A display that isn't attached
    keeps its old picture until a space change happens while it is plugged in;
    its entry in the store is regenerated even if deleted by hand.
  - The watcher is armed for the **Hammerspoon session**, not persisted. Reload
    the config before you have visited every space and the stragglers wait for
    the next switch to re-arm it — which is why activation arms it on every
    run, whatever the guard decided.
  - `hs.screen:desktopImageURL` wants a percent-encoded `file://` URL and
    raises an Obj-C exception on a bare path. `hs.fs.urlFromPath` builds one
    through NSURL, so it compares equal to what the getter returns, and is
    `nil` for a file that isn't there — which doubles as the check for a
    library Resilio hasn't synced yet.
  - The **screen saver** is the other half of the same store, so it is not
    declarable at all, and Hammerspoon doesn't rescue it either —
    `hs.caffeinate` can start a saver but not choose one.
    `modules/darwin/defaults.nix` says so where the option would otherwise go.
- **Registry + NIX_PATH**: `nix.registry.nixpkgs.flake = inputs.nixpkgs` and a
  flake-pinned `nix.nixPath` keep both `nix shell nixpkgs#foo` and
  `nix-shell -p foo` working.
- **A file in `dotfiles/` is not a linked file.** homeshick linked whatever was
  in the castle; here every path needs a declaration, and a tracked file nobody
  declared is simply absent on the machine — which looks like a broken feature,
  not a missing symlink (`eza-wrapper.sh` was one: `ls` aliased to a path that
  didn't exist). What's still unlinked, as of that fix:

  ```
  nix eval --raw \
    .#darwinConfigurations.ala.config.home-manager.users.jamie.home.file \
    --apply 'f: builtins.concatStringsSep "\n" (builtins.attrNames f)'
  # compare against `git ls-files dotfiles/home` — note the xdg module rewrites
  # xdg.configFile keys to absolute paths, so normalize before diffing
  ```

  A prefix match against that list has a blind spot: a directory declared with
  `recursive = true` covers its own files, not files the tree adds beside them.
  `.config/nvim` is the one that bit — sourced recursively from the neovim
  input, so every session file under `dotfiles/home/.config/nvim/sessions`
  looked declared and none of them were.

  - `.config/gh/config.yml`, `.config/op/plugins.sh` — both rewritten by their
    own tool; nothing sources `plugins.sh` yet either (see SECRETS.md).
  - `.config/stay/action-*.{sh,applescript}` — invoked by Stay, whose own config
    lives in `Library`. Still carrying `/Users/jamie` hardcodes.
  - `.skhdrc` — `services.skhd.enable = false`, so this is dead weight until it
    isn't.
  - `.terminfo/*` — compiled entries; nix's ncurses covers `tmux-256color`.
  - `Documents/Obsidian/Brain/.obsidian/*`, `Library/…/Firefox/…/user.js`,
    `Library/…/Plex/{input,mpv}.conf` — app-managed, and the Obsidian vault is a
    Resilio share on the machines that have it.

- **The kitty dotfiles layout follows the repo consolidation.** It opened a tab
  per castle, each loading a matching nvim session; two of those castles are one
  repo now. `sessions/dotfiles.kitty-session`:

  | tab | was | is |
  | --- | --- | --- |
  | `system` | `dot` + `macos` tabs, `dot--{dot,macos}.vim` | `~/.config/system`, `system.vim` |
  | `neovim` | `~/.homesick/repos/neovim`, `dot--neovim.vim` | `~/Developer/Sources/jrolfs/neovim`, `neovim.vim` |
  | `private` | `~/.homesick/repos/private`, `dot--private.vim` | unchanged — still a castle |

  Two tabs on one repo would have bought nothing: the sessions end in
  `Telescope git_files`, whose `use_git_root` defaults on, so a tab lcd'd into
  `dotfiles/` picks from the same list as one at the root.

  The neovim tab needs the clone, and it can't be `~/.config/nvim`: that's a
  tree of symlinks, and it wasn't a git repo at all while it pointed into the
  store, so `git_files` errored there (`… is not a git directory`).
  `home.activation.neovimConfigClone` now makes the clone on every machine.

  `neovim.vim` moved *into* this repo rather than staying in the neovim one:
  `:mksession!` rewrites the file it was loaded from, and `sessions/` is the one
  part of the config tree that isn't linked to the clone, so a session there
  would have nowhere to land. The neovim repo's own `sessions/dot--neovim.vim`
  is no longer linked anywhere and can go next time that repo is touched.

  Two files left alone because nothing reads them, both still on castle paths:
  `kitty/sessions/startup.conf` (a superseded copy of the whole multi-window
  layout — `kitty.conf`'s `startup_session` names `dotfiles.kitty-session`) and
  `nvim/sessions/dot.vim` (the pre-split session that held all four repos as
  tabs in one nvim). Deletion candidates rather than things to keep in sync.

## Pinning / overlays

- **`overlays/pin.nix`** — pin a single package to an older nixpkgs revision
  (via `builtins.fetchTarball`) when the current rev isn't cached yet
  (aarch64-darwin lags). Prints live cache status each rebuild so you know when
  the pin is safe to remove.
- **`masterPkgs`** — `inputs.nixpkgs-master` provides bleeding-edge builds
  (e.g. `spicetify-cli`). Bump with `nix flake update nixpkgs-master`.
- **`zshcs`** (Zsh LSP) — built by the overlay from `inputs.zshcs`
  (`flake = false`). Was previously pinned via npins; **npins was dropped** —
  everything is flake-managed now.
- Overrides that disable sandbox-hostile/naive tests when building from source:
  `mcp-nixos` (`test_read_text_file`), `worktrunk` (process-table probes).

### Reference — pinning old package versions

`nixpkgs-multiverse` (https://fzakaria.com/2026/08/09/nixpkgs-multiverse-every-version-that-ever-existed)
makes every historical nixpkgs version addressable — worth trying if `pin.nix`
becomes unwieldy or a package needs a precise old version. Not adopted yet.

## Bootstrap (`jrolfs/bootstrap`)

Fresh-machine installer, two stages: `bootstrap.sh` (bash) installs **Lix** +
Xcode CLT and clones itself (`BOOTSTRAP_REF` selects the branch, defaulting
to `main`), then a Deno/TS app runs an
ordered, resumable set of phases (state in `~/.bootstrap/state.json`; re-run
the one-liner to resume). macOS-only steps are gated on `Deno.build.os`.

Run it on a fresh machine:

```sh
bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/jrolfs/bootstrap/main/bootstrap.sh)"
```

On NixOS the same command runs from the installer image: it partitions the
disk and installs the system, then you reboot and run it again for the
user-level phases.

Phases, in order:
1. **hostname-set** — confirm/set the hostname *first* (the flake selects its
   host config by it). macOS sets HostName + LocalHostName + ComputerName +
   flushes DNS; Linux uses `hostnamectl`. The chosen name is persisted and used
   for the flake selector, not a live re-read (a fresh Mac's `hostname` is often
   a DHCP/marketing name, not e.g. `ala`).
2. **github-authed** — device-flow auth, mint + upload an SSH key.
3. **homebrew-installed** → **op-installed** → **op-authenticated** (enable the
   1Password GUI's CLI integration; verified via `op whoami`).
4. **private-cloned** (homeshick clone + `link private`) → **nix-config-cloned**
   (`nixConfigRepo`@`nixConfigBranch` → `~/.config/system`; currently
   `jrolfs/macos`@`main` — flip the repo name after the rename) →
   **vscode-sync-cloned**.
5. **resilio-configured** — install Resilio, best-effort seed `sync.conf`, launch
   foreground and **guide the user** through the first-run EULA + adding the
   `~/Configuration` share (secret pulled via `op`, shown on screen). The GUI app
   manages folders in its own storage, so the manual add is surfaced with a
   pause rather than assumed. Then wait for `~/Configuration/mackup` to sync.
6. **first-switch-completed** — `darwin-rebuild`/`nixos-rebuild switch --flake
   ~/.config/system#<hostname>` (first run bootstraps the tool via `nix run`).
7. **mackup-restored** — confirmed `mackup restore -f` from the synced
   `~/Configuration/mackup` (mackup is installed by the switch). Skips cleanly if
   not ready; `mkrs` remains available.

Post-switch, by hand:

- Grant Full Disk Access to `/usr/local/bin/icon-customizer`.
- Grant Accessibility to Hammerspoon. Half its modules need it (the wallpaper
  only needs it for `M.walk()`, not for the watcher).
- Add `~/Images` as a Resilio share, the same way phase 5 does `~/Configuration`
  — the wallpaper library lives in it. Until it syncs, `modules/home/
  wallpaper.nix` leaves the stock desktop alone rather than pointing at a file
  that isn't there (which paints it black).
- System Settings → Wallpaper → **Add Folder…** → `~/Images/Wallpapers`, if you
  want to browse the library in the picker. Deliberately not declared: the
  entry macOS stores (`com.apple.wallpaper.extension.image` →
  `ChoiceRequests.ImageFolders`) is a security-scoped bookmark carrying the
  volume UUID plus a path into the extension's own container cache, so it is
  machine-specific by construction. Picking the wallpaper is declared instead,
  which is the part that mattered.

## Phases

1. **Ala** (new Mac) — flake conversion + home-manager + dotfile audit.
   `darwin-rebuild build --flake .#ala` is the gate; then bootstrap a clean Ala.
2. **Irulan** (NixOS NUC, Beelink SEi 12 / i5-12450H) — home-server workload off
   the QNAP. Native `services.{home-assistant,plex,step-ca}`; Komodo core+mongo
   +periphery as bootstrap-tier `virtualisation.oci-containers`; traefik/pi-hole
   /matter stay Komodo-deployed from the compose repo. Plex uses Quick Sync
   (`hardware.graphics` + `intel-media-driver`); media over NFS from the QNAP;
   Pi-hole keeps its LAN IP via macvlan. `hosts/irulan/hardware-configuration.nix`
   is generated on the box at install time. See `modules/nixos/services/`.

   **Resilio on Irulan** — Resilio stays the mechanism for non-git sync, and
   NixOS has a first-class module: `services.resilio.enable` +
   `services.resilio.sharedFolders` (declarative shares), which is the right
   approach here rather than the imperative `sync.conf` seeding the macOS
   bootstrap does. Three caveats when wiring it up:
   - The daemon runs as the `rslsync` system user, so a path under
     `/home/jamie` needs `rslsync` group ownership + `chmod g+s` + `setfacl`
     (see the option docs) — or pick a path outside `$HOME`.
   - `sharedFolders` puts the share secret in the **world-readable nix store**;
     source it from **agenix/sops-nix** instead of inlining it.
   - `sharedFolders` requires the web UI off (`enableWebUI = false`).

   **Share layout wants optimizing first** (deferred until Ala is working —
   ideally done before Irulan). `~/Configuration` is ~1.3 GB, of which ~1.29 GB
   is macOS-only: Mackup 610M, Raycast 547M, Alfred 97M, Shimo 36M, plus
   Dash/Stay/Arq/Photoshop prefs. The portable remainder is ~44 KB —
   `Certificates/` (step-ca `*.rolfs.lan` leaf certs + root CA), `Networking/`
   (wgcf account + WireGuard profile), `Nuphy/` (keyboard-configurator JSON).
   Subscribing Irulan to the whole share would pull 1.3 GB for 44 KB, so split
   into a macOS-only share and a portable one before Irulan subscribes. Note
   Irulan runs step-ca itself, so it needs the migrated CA data, not synced
   leaf certs.

   Also worth revisiting independently: `Networking/wgcf-*` is a WireGuard
   private key + account token and `Certificates/` is LAN PKI, both currently
   replicated in cleartext across devices and Resilio relays. The git-crypt'd
   `private` castle may be the better home for those two specifically.
3. **Newt** (daily driver) — migrated last, once Ala + Irulan are proven.
   Back up `~/.homesick`, `homeshick unlink dot macos neovim` (leave
   `private`), `mv ~/.homesick/repos/macos ~/.config/system`, add
   `hosts/newt/`, switch. Consider `cleanup = "uninstall"` (not `zap`) for the
   first switch.

   Push the neovim castle's working copy *first* — the switch clones a fresh
   `~/Developer/Sources/jrolfs/neovim` from the remote and nothing carries local
   commits or dirty files across (there are 5 modified nvim files sitting in
   `~/.homesick/repos/neovim` as of this writing).

   `hosts/newt/` needs `ids.gids.nixbld`, which nothing in the flake sets
   because Ala's Nix install uses the current group ID. Newt's predates the
   change, so nix-darwin's assertion fails unless the real one is read off the
   machine — `macos` master carries this as a `dscl . -read /Groups/nixbld
   PrimaryGroupID` lookup in `darwin-configuration.nix` (restored in `1b52045`
   after an attempt to drop it). Host-local, so it belongs in `hosts/newt/`
   rather than a shared module.

## Secrets & private configuration

Getting off git-crypt, splitting genuine secrets (→ 1Password) from private
non-secret overlays (→ plain symlinks), and `bootstrap secrets` to manage the
`op://` references. See [SECRETS.md](SECRETS.md) — independent of this
migration; the prune and split steps can happen on either side of it.

## Backporting fixes to the pre-migration setup

`newt` runs the old setup until phase 3, so bugs found while migrating often
still affect it. Candidates are tracked in [BACKPORT.md](BACKPORT.md) — with the
`OP_CONFIG_DIR` device-local-state fix being the one that actively matters today.

## Keeping up with drift (until phase 3)

The old `dot` / `macos` `master` branches are still edited via homeshick until
Newt migrates, so periodic forward-ports are needed:

- **neovim**: nothing, as long as the clone is what you edit — the links are
  live. `nix flake update neovim-config` is only for a new *top-level* entry in
  that repo (see the architecture note). Newt is the exception until phase 3:
  it still edits the castle at `~/.homesick/repos/neovim`, so push from there
  and the clone on the other machines picks it up with a `git pull`.
- **dot** (content, no moves): merge `master` into the `audit-cleanup` branch,
  then `git subtree pull --prefix=dotfiles <dot> audit-cleanup`. Expect a
  `.zshrc` conflict on the zinit source line — keep `$XDG_DATA_HOME/zinit/…`,
  take dot's other additions. The `master` merge also hits a modify/delete
  conflict on any submodule `master` bumps and `audit-cleanup` deleted
  (`kitty-grab`, `zinit`, the theme trees): resolve by keeping them deleted —
  `git rm --cached <path> && rm -rf <path>` — and, if the bump matters, move the
  new revision into the matching flake input instead. This recurs on every pull
  for as long as dot `master` carries the submodules.
- **macos**: the migration *moved* these files, so don't cherry-pick — re-derive
  `modules/darwin/*` from `home/.nixpkgs/*` and re-apply the transforms above,
  and copy changed dotfiles from `home/*` into `dotfiles/home/*` and
  `icons/` / `homebrew/` / `.mcp.json` at the root.

Retire the homeshick-on-old-repos workflow soon to end the catch-up treadmill.
