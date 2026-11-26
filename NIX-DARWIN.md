# nix-darwin module coverage (2026-09-26)

A pass over every module nix-darwin ships, recording which of its options this
repo sets, which it deliberately doesn't, and what is still open. `newt` is the
reference for values: it is the machine with years of hand-tuning behind it, and
it still runs the pre-flake homeshick setup (`pre-flake` branch plus the `macos`
castle), so anything it does that the flake doesn't is drift rather than a
decision.

Counts below are against nix-darwin `4cff07d` (the flake lock at the time) and
the `ala` host.

## Method

Coverage is measured rather than eyeballed. Every evaluated option carries both
`declarations` (which module declared it) and `definitionsWithLocations` (which
files defined it), so partitioning by store path separates nix-darwin's own
defaults from this repo's:

```nix
# nix eval --json --impure --file ./coverage.nix
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  safe = f: d: let r = builtins.tryEval f; in if r.success then r.value else d;
  walk = path: attrs:
    lib.concatLists (lib.mapAttrsToList (n: v:
      if n == "_module" then [ ]
      else if safe (lib.isOption v) false then
        [{
          name = lib.concatStringsSep "." (path ++ [ n ]);
          decl = safe (map toString (v.declarations or [ ])) [ ];
          defs = safe (map (d: toString (d.file or "?")) (v.definitionsWithLocations or [ ])) [ ];
        }]
      else if safe (lib.isAttrs v && !(lib.isDerivation v)) false then walk (path ++ [ n ]) v
      else [ ]
    ) attrs);
in walk [ ] flake.darwinConfigurations.ala.options
```

`tryEval` is not decoration: `networking.fqdn`'s default throws when nothing
sets `networking.domain`, and forcing it unguarded aborts the whole walk.

Result: **747 options declared by nix-darwin**, of which this repo defines
**131**, across 20 files (96 of them in `modules/darwin/defaults.nix` alone).
The other 616 are the subject of the rest of this file.

A nix-darwin option being unset says nothing on its own, so each of the 119
unset `system.defaults` keys was compared three ways: read on `newt`, read on
`ala`, and checked against the option's documented default.

Read **one key at a time** (`defaults read <domain> <key>`), not by parsing a
whole-domain dump. `defaults read com.apple.finder` returns nested dictionaries,
and a line-oriented parse of that silently reports set keys as absent: the first
attempt here lost `finder.ShowStatusBar`, which is set on both machines. A
per-key read either returns a value or exits non-zero, with no parsing in
between.

Results across the 119:

| | count | meaning |
|---|---|---|
| unset on both | 85 | at Apple's default, nothing to capture |
| set and equal on both | 27 | see below |
| differ between machines | 7 | see below |

Of the 27 set on both, most hold the stock value (the key exists because
something touched the pane, not because a choice was made), and two are already
declared through the `controlcenter` ByHost block. Three are genuinely
non-default and are what this pass captured.

**Caveat on the remaining six.** nix-darwin's "The default is ..." sentences are
not all current. It documents `trackpad.TrackpadPinch` (pinch to zoom),
`TrackpadRotate`, `TrackpadTwoFingerDoubleTapGesture`,
`TrackpadFourFingerPinchGesture`, `TrackpadFourFingerHorizSwipeGesture` and
`TrackpadTwoFingerFromRightEdgeSwipeGesture` as defaulting to off, while macOS
ships every one of them on, which is exactly what both machines show. Treating
that text as authoritative would have declared six gestures nobody chose. They
are left alone; see the candidates section if pinning them against a future
Apple change is wanted anyway.

## What this pass changed

1. **`modules/darwin/spotlight.nix` restored.** It exists on `pre-flake` and on
   `newt`, and the migration dropped it. That matters more here than it did
   there: `modules/darwin/mas.nix` drives `mas list` directly, and `mas list`
   reads App Store installs out of the Spotlight index. With indexing off it
   returns nothing and exits 0, so every app in the list looks missing and gets
   reinstalled on every switch.

2. **`modules/darwin/tailscale.nix` ported.** Never migrated (`newt` commit
   `0cdb82e`, listed as gap 2 in RECONCILIATION.md). Connect everywhere except
   at home, decided here and applied through `tailscale up` / `tailscale down`
   rather than through macOS on-demand VPN, which flaps and strands the
   resolver. One change was needed for the flake: the log path came from
   `builtins.getEnv "XDG_DATA_HOME"`, which is empty under pure evaluation, so
   it is derived from `system.primaryUser` instead. Verified on `ala`:
   `tailscale-auto status` fingerprints the home gateway, reports `location:
   home`, and leaves the client `Stopped`.

3. **Three `system.defaults` keys that both machines set and neither declared:**
   `finder.ShowStatusBar`, `WindowManager.EnableTilingOptionAccelerator` and
   `trackpad.TrackpadThreeFingerTapGesture`. See the module comments for why
   each one is where it is.

`login-items.nix` is **not** a gap despite RECONCILIATION.md listing it as one:
it was ported after that file was written, and the flake copy is ahead of
`newt`'s (it handles login items whose app has been deleted, and documents the
`app` versus `login item` record distinction).

## Managed today

`system.defaults`: `NSGlobalDomain` (33/54), `dock` (16/34), `finder` (13/20),
`WindowManager` (8/12), `trackpad` (5/22), `clock` (3/8), `loginwindow` (2/12),
`smb` (2/2), `ActivityMonitor`, `CustomUserPreferences`, `.GlobalPreferences`,
`LaunchServices`, `SoftwareUpdate`, `hitoolbox`, `spaces`, `screencapture`.

Elsewhere: `homebrew` (7/23), `nix` (5/37), `networking` +
`networking.applicationFirewall` (7/16), `programs.zsh` (3/17),
`services.postgresql`, `power.sleep`, `programs.ssh`, `security.pam`,
`services.openssh`, `services.skhd`, `system.activationScripts`,
`environment.etc`, `system.startup`, `system.stateVersion`,
`system.primaryUser`, `launchd.user.agents`, `environment.systemPackages`,
`nixpkgs`, `time.timeZone`, `users.users`.

A low ratio is not a gap by itself. `NSGlobalDomain` at 33/54 is what it looks
like when 18 of the 21 unset keys are unset on both machines too and the other
three hold stock values, which is what the per-key comparison found.

## Deliberately not used, with the reason

These are decisions, not omissions. Most are already argued in the module that
declines them; this is the index.

- **`system.defaults.universalaccess`** and **`system.defaults.screensaver`**:
  both argued at length in `modules/darwin/defaults.nix`. universalaccess is
  TCC-protected and the activation write always fails; the screen saver moved
  into the WallpaperAgent store and the legacy domain is a mirror, not the
  source.

  This pass did turn up live drift behind that decision, which is worth knowing
  precisely because nothing will close it automatically:
  `universalaccess.closeViewScrollWheelToggle` is 1 on `newt` and unset on
  `ala` (corroborated by `HIDScrollZoomModifierMask = 262144`, the Control key,
  in newt's trackpad domain). That is zoom-on-scroll, and it needs the one-time
  click in System Settings → Accessibility → Zoom that defaults.nix describes.
  Likewise `screensaver` ByHost has `moduleName = Drift` on `newt` and nothing
  on `ala`. Both are per-machine manual steps by design, not missing config.
- **`system.defaults.controlcenter`**: reached through
  `CustomUserPreferences` against the ByHost path instead, because the module's
  bool options can only ever write 18 or 24, and the menu bar needs the other
  integers.
- **`system.defaults.alf`**: superseded by `networking.applicationFirewall`,
  which is set. Setting both would be two writers for one firewall.
- **`programs.mas`**: `modules/darwin/mas.nix` replaces it. Its activation
  script interpolates a bare `exit 0` for the not-signed-in case, which exits
  activation itself and silently skips Homebrew and everything after it.
- **`homebrew.masApps`**: same, App Store installs do not go through
  `brew bundle` here.
- **`services.tailscale`**: runs `tailscaled` from nixpkgs. The machines run the
  Tailscale app (a cask) with its system extension, which is what
  `modules/darwin/tailscale.nix` drives.
- **`services.karabiner-elements`**: Karabiner comes from the cask, which is the
  supported way to get its driver extension approved.
- **`programs._1password`, `programs._1password-gui`**: both casks.
- **`fonts.packages`**: every font is a Homebrew cask today, so that the same
  names are available to apps that look fonts up by family. Worth revisiting,
  but it is a choice rather than an oversight.
- **`system.keyboard`**: Karabiner owns remapping (Caps Lock to Right Control,
  Fn+HJKL to arrows). `system.keyboard.userKeyMapping` is a second writer for
  the same hardware and would fight it.
- **`misc.ids.gids.nixbld`**: only needed for Nix installs predating the group
  ID change. Noted in `hosts/adrian/default.nix` as not needed there or on
  `ala`; `newt` did need it.
- **Tiling and bar services** (`yabai`, `aerospace`, `jankyborders`,
  `sketchybar`, `spacebar`, `chunkwm`, `khd`, `kwm`): not the window management
  in use. Moom and Stay are, and `services.skhd` is explicitly `enable = false`.

## Not applicable

Server and Linux-desktop territory, listed so a future pass does not re-derive
it: `gitlab-runner`, `github-runner`, `buildkite-agents`, `hercules-ci-agent`,
`ofborg`, `cachix-agent`, `synergy`, `ipfs`, `synapse-bt`, `mopidy`, `spotifyd`,
`trezord`, `emacs`, `offlineimap`, `privoxy`, `dnsmasq`, `dnscrypt-proxy`,
`nextdns`, `netbird`, `wg-quick`, `eternal-terminal`, `autossh`, `lorri`
(superseded by direnv plus nix-direnv), `redis`, `netdata`, `telegraf`,
`prometheus-node-exporter`, `arqbackup` (the cask is installed, the module
configures a licence server), `devenv`/`direnv`/`fish`/`bash`/`tmux`/`vim`/
`nix-index`/`info`/`man` (shell and tool config is home-manager's, not
nix-darwin's), `documentation`, `config.terminfo`, `system.newsyslog`,
`system.nvram`, `system.patches`, `security.sandbox`, `alias`, `meta`,
`misc.lib`.

## Open candidates

Nothing here is drift from `newt`: these are options neither setup uses, found
by walking the module list. Each is a real behaviour change, so they are listed
rather than adopted.

1. **`nix.gc.automatic` / `nix.optimise.automatic`.** No garbage collection or
   store optimisation is scheduled on any host. Both are `launchd.daemons` with
   a `StartCalendarInterval`. The reason to think before enabling: GC deletes
   build results that nothing roots, which on a machine that builds nix-darwin
   closures all day is a real cache to throw away.
2. **`nix.settings.trusted-users`.** `/etc/nix/nix.conf` currently has
   `trusted-users = root`. Adding `@admin` is what lets a non-root `nix build`
   use extra substituters and accept `nix copy` pushes. It also means any admin
   user can point the daemon at a cache, which is the trade.
3. **`security.pam.services.sudo_local.reattach`.** `touchIdAuth` is on, and
   `pkgs.tmux` is in `modules/packages.nix`. Touch ID for sudo does not work
   inside a tmux or screen session without `pam_reattach`, so this is the
   missing half of a setting already made.
4. **`security.pam.services.sudo_local.watchIdAuth`.** Same file, Apple Watch
   instead of the sensor. Only worth setting if there is a Watch.
5. **`homebrew.greedyCasks`.** `onActivation.upgrade` is `true`, but casks that
   self-update (1Password, Chrome, Raycast, Zed, Cursor, ChatGPT, Claude) are
   skipped by `brew upgrade` unless named greedy, so today they are upgraded by
   themselves and not by a switch. Listing them makes switches slower and their
   versions reproducible; leaving them makes switches faster and their versions
   whatever the app last fetched.
6. **`homebrew.caskArgs`.** `no_quarantine` is the common one. Note
   `system.defaults.LaunchServices.LSQuarantine = false` is already set, which
   covers most of the same ground.
7. **`nix.channel.enable = false`.** The repo is flakes-only and pins
   `nix.nixPath` explicitly, so the `nix-channel` command and its state files
   are dead weight. Setting this to false removes `nix-channel` from the system
   profile. Verify nothing shells out to it first.
8. **`nix.linux-builder.enable`.** `irulan` is `x86_64-linux` and is built on
   the box today. A linux-builder VM would let a Mac build and push its closure
   instead. Costs a resident VM and disk.
9. **`security.pki.certificateFiles`.** `irulan` runs step-ca
   (`modules/nixos/services/step-ca.nix`) and the Macs do not trust its root
   from nix. Adding the root here puts it in the system bundle rather than
   needing a keychain import per machine.
10. **`system.configurationRevision`.** Stamps `darwin-version` with the git
    revision, so a machine can say which commit it is running. Cheap, and it
    makes `self.rev` meaningful on a dirty tree only if guarded.
11. **The six trackpad gestures nix-darwin mis-documents** (see the caveat in
    Method). Both machines hold macOS's current values. Declaring them would
    pin gestures against a future Apple change at the cost of writing down six
    settings nobody picked. Listed because "unset" here means "trusting Apple",
    not "at the documented default".

## What to re-run

The coverage expression in Method is the whole audit. Re-run it after a
`nix flake update` that moves nix-darwin: new modules and new
`system.defaults` keys appear there first, and the three-way defaults
comparison against a reference machine is what turns an unset option into
either "already at Apple's default" or "drift".
