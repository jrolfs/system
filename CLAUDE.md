# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What This Is

One flake that configures every machine Jamie owns, macOS and Linux alike,
from a single source. `nix-darwin` builds the macOS systems, `home-manager`
owns the dotfiles, and `nixpkgs` is pinned by `flake.lock`.

It deploys to `~/.config/system` on a machine.

Hosts (`flake.nix`):

| Attribute | Machine |
|---|---|
| `darwinConfigurations.ala` | MacBook Air M4, personal |
| `darwinConfigurations.adrian` | MacBook Air M5, work, MDM-managed |
| `nixosConfigurations.irulan` | Beelink NUC home server (`x86_64-linux`) |

`newt` is the retired work laptop that `adrian` replaces. Its attribute is
commented out in `flake.nix`, but the machine still runs the pre-flake
configuration (the `pre-flake` branch plus the `macos` homeshick castle), which
makes it the reference for anything not yet migrated. See documentation/MIGRATION.md.

The migration from homeshick castles and nix channels is still in progress. The
`private` castle deliberately stays a castle (git-crypt), which is why
`$HOMESHICK_KINGDOM` is still exported. documentation/SECRETS.md covers that half.

## Key Commands

```bash
# Build and activate this host. Generated for every machine by
# modules/home/shared/nix-commands.nix, with platform flags from modules/home/{darwin,linux}/default.nix.
nix-switch
nix-switch --pull       # fast-forward the tree being switched first, from anywhere
nix-switch --worktree=<branch>  # switch a worktree's flake instead of main's
nix-switch --main       # main checkout, even from inside a worktree
wt verify               # is the running system exactly this worktree's build?
wt land                 # wt merge (rebase, commits kept), then nix-switch --main
nix-switch --update     # refresh flake.lock first (--update=nixpkgs for one input)
nix-switch --brew       # macOS: run `brew bundle` even if the Brewfile is unchanged
nix-switch --no-brew    # macOS: skip it for one switch

nix-rebuild             # build without activating
nix-update              # nix flake update, optionally per-input
homebrew-gate status    # whether the next switch will run `brew bundle`

velja-rules diff        # has Velja drifted from modules/darwin/velja/rules.toml?
velja-rules capture --write   # pull GUI-authored rules back into rules.toml
velja-rules apply       # push rules.toml into Velja without a full switch

icn                     # apply custom app icons (icons/apply.sh)
mkbk / mkrs             # mackup backup / restore
spoon                   # the Hammerspoon CLI (`hs` is homeshick)
```

`brew bundle` is the slowest part of a switch and is gated on a content hash of
the Brewfile, so most switches skip it. That gate is the reason `--brew` exists:
a version bump inside a `jrolfs/tap` cask does not change the Brewfile.

On Linux hosts `nix-switch` wraps `nixos-rebuild` instead.

Worktrees of this repo live in `~/.config/.system/<branch>`, set by the
`worktree-path` entry in `dotfiles/home/.config/worktrunk/config.toml`. Run from
inside one, a bare `nix-switch` switches that worktree's flake and says so, and
the next switch from the main checkout puts main back. Not nested under the
checkout because Claude Code loads `CLAUDE.md` from every parent directory, so
a nested worktree session would also load main's copy.

## Layout

```
flake.nix          inputs, the three host configurations, the `glide` devShell
modules/
  shared/          system configuration every host gets, macOS and Linux alike
    packages.nix     packages every machine gets
    bootstrap.nix    the `bootstrap` CLI, for 1Password-backed secrets
    home-backup.nix  what home-manager does with an unmanaged file in its way
  darwin/          macOS system configuration (nix-darwin)
  nixos/           NixOS system configuration
  home/            home-manager, split the same way:
    shared/          every machine
    darwin/          macOS only
    linux/           Linux only, including the Hyprland desktop
  theme/           palette and fonts, read by both platforms
hosts/             per-host overrides: ala, adrian, irulan (+ irulan/disko.nix)
dotfiles/home/     the dotfile tree, linked into $HOME by modules/home
documentation/     the companion docs listed below
homebrew/          IS the jrolfs/tap, symlinked into brew's Taps directory
icons/             .icns assets plus apply.sh
karabiner/         live Karabiner config, out-of-store symlinked so it can write back
overlays/          nixpkgs overlays, plus pin.nix for single-package pins
automator/         macOS Automator workflows
vscodium/          separate flake building VSCodium with extensions
links/             convenience symlink to /Library/LaunchDaemons
```

### modules/darwin

| Module | What it does |
|---|---|
| `defaults.nix` | `system.defaults`, the bulk of the macOS preferences |
| `homebrew.nix` | casks, brews, taps, and the `brew bundle` gate |
| `tap.nix` | symlinks `homebrew/` into place; `cask-updater` bumps the casks |
| `mas.nix` | App Store installs, driving `mas` directly (not via `brew bundle`) |
| `spotlight.nix` | keeps Spotlight indexing on, which `mas list` depends on |
| `excluded-apps.nix` | per-host cask/App Store exclusions, read by both of the above |
| `login-items.nix` | login items via System Events, since the BTM store is SIP-locked |
| `startup.nix` | Spotify and Fantastical autostart, via their own settings |
| `daemons.nix` | launchd user agents, for headless things only |
| `tailscale.nix` | connect Tailscale everywhere except at home |
| `finder-sidebar.nix` | Finder sidebar Favorites, via `mysides` |
| `folder-icons.nix` | SF Symbol / emoji icons on `$HOME` folders, over Resilio's |
| `default-browser.nix` | Velja as the http(s) router |
| `velja/` | Velja's settings, plus `rules.toml` and the `velja-rules` CLI |
| `icons.nix` / `fileicon.nix` | custom app icons and the tool that sets them |
| `fda.nix` | the one Full Disk Access grant, and the shim everything needing it runs through |
| `accessibility.nix` | Accessibility Zoom, written through that shim |
| `sidecar.nix` | Sidecar (iPad as display) via the private SidecarCore framework |
| `glide-developer.nix` | a second Glide copy with its own bundle identifier |
| `kaset.nix` | source build with the native-PiP patch, or the stock cask |
| `spicetify.nix` | Spotify theming |

### modules/home

home-manager configuration, in the same three layers as the system side.
`flake.nix` loads `shared/` for every user and adds `darwin/` or `linux/` as a
home-manager shared module by platform, so a module's directory is what decides
where it applies.

- `shared/`: `default.nix` links `dotfiles/home` into `$HOME`; beside it
  `neovim.nix` (owns all of `~/.config/nvim`), `ssh.nix`, `atuin.nix`,
  `claude-sync.nix`, `onepassword.nix` (the `op` those two read through),
  `gh.nix`, `starship.nix`, `mcp.nix`, `nix-commands.nix`, `eza.nix`.
- `darwin/`: `default.nix` plus `browsers.nix`, `zed.nix`, `raycast.nix`,
  `wallpaper.nix`, `icloud.nix`.
- `linux/`: `default.nix` plus `desktop/`, the Hyprland session.

## Companion docs

Read the relevant one before changing that area. They carry the reasoning that
would otherwise have to be rediscovered.

| File | Covers |
|---|---|
| `documentation/NIX-DARWIN.md` | every nix-darwin module, and whether this repo uses it |
| `documentation/MIGRATION.md` | the homeshick-to-flake migration, phases and gotchas |
| `documentation/RECONCILIATION.md` | the castle-to-flake file sweep, and what still needs a decision |
| `documentation/BACKPORT.md` | fixes found here that newt's pre-flake setup still needs |
| `documentation/HOMEBREW.md` | how far Homebrew determinism goes, why `brew pin` and nix-homebrew don't get there |
| `documentation/SECRETS.md` | why secrets sit outside the flake, and the bootstrap dependency chain |
| `documentation/ZSH.md` | moving zsh plugins from zinit to Nix, and the startup-time baseline |
| `documentation/ARCADE.md` | Irulan's emulator station: ROM and BIOS layout, switching, scraping, controllers |
| `documentation/IRULAN-MIGRATION.md` | moving Leia's services to Irulan: what goes where, the phases, and how Komodo spans both hosts |
| `homebrew/README.md` | the tap itself, and bumping a cask with `cask-updater` |

## Conventions

- Flakes only. `nix.nixPath` and the registry are pinned to the flake's inputs
  in `modules/shared/nix.nix`, so `nix shell nixpkgs#foo` resolves to the
  same nixpkgs the system was built from.
- `allowUnfree`, `allowBroken` and `allowUnsupportedSystem` are all on.
- Homebrew cleanup is `zap`, so any cask not listed is removed on the next
  switch. `onActivation.upgrade` is `true`, which is deliberate and argued in
  `homebrew.nix`.
- Touch ID for sudo via `security.pam.services.sudo_local.touchIdAuth`.
- `nix.package` is Lix, the same release on every machine, set in
  `modules/shared/nix.nix`.
- Comments explain *why*, not what. Most modules here open with a paragraph on
  the failure they exist to prevent; match that rather than summarising the
  code.
- The repo's own small tools are Rust, built by `pkgs.rustTool` (and
  `pkgs.rustLibrary` for code they share) in `overlays/default.nix`. One
  `rustc` for all of them, invoked bare rather than through Cargo, so a tool is
  a single `.rs` file in `modules/darwin/pkgs/` with no manifest or lock file.
  That overlay is also where the non-obvious flags are explained; add tools
  through it rather than calling `rustc` or `$CC` from a module. `sidecar.swift`
  stays Swift because it needs the macOS SDK's private frameworks.

## Gotchas

- **`builtins.getEnv` returns `""` under pure flake evaluation.** Several
  modules carry a hardcoded path with a comment saying exactly this
  (`icons.nix`, `spicetify.nix`, `tailscale.nix`). Deriving from
  `config.system.primaryUser` is the pattern. A path that silently becomes
  `/foo` instead of `/Users/jamie/foo` fails at runtime, not at build time.
- **A nix-darwin option being unset means nothing on its own.** It may be at
  Apple's default, or it may be drift. Check the machine before declaring
  anything, and read `defaults` one key at a time: parsing a whole-domain
  `defaults read` reports set keys as absent, because the output is nested.
- **nix-darwin's "The default is ..." documentation is not always current.** It
  describes several trackpad gestures as defaulting to off that macOS ships on.
  documentation/NIX-DARWIN.md lists the known-stale ones.
- **Per-host exclusions live in `excluded-apps.nix`**, keyed by short hostname.
  The old `NIX_MACOS_EXCLUDE_CASKS` environment variable is dead; the
  `dotfiles/home/.config/zsh/env.*` files that still set it are leftovers and
  nothing reads them.
- **Some macOS state is not declarable at all**, and the modules say so where it
  bites: the screen saver and wallpaper (WallpaperAgent owns the store), and
  desktop widget placement (an NSKeyedArchiver graph in chronod's sqlite). These
  are per-machine manual steps by design, not missing configuration.
- **A domain needing Full Disk Access is declarable, just not from activation.**
  `com.apple.universalaccess` is the worked example. nix-darwin writes user
  defaults through `launchctl asuser ... sudo --user=...`, which holds no grant,
  so `system.defaults.universalaccess` fails with "Could not write domain" and
  takes the rest of activation down with it under `set -e`. Route it through
  `fda.nix` instead: register an `fda.operations.<name>` and have a LaunchAgent
  call `fda-run <name>`. The grant is keyed on the shim's cdhash, so a rebuild
  that changes those bytes revokes it; the dispatcher probes for it and
  notifies, and `77: EX_NOPERM` from one of those agents means exactly that.
