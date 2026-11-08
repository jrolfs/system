# The emulator station

Irulan's game menu on the TV: Pegasus, fullscreen in gamescope, launching
each game in RetroArch with the right core. It runs as its own `arcade` user,
on virtual terminal 7, beside the desktop on tty1. Configured by
`modules/nixos/arcade/`, switched on by `arcade.enable = true;` in
`hosts/irulan/default.nix`.

## Switching between the station and the desktop

| How | What |
|---|---|
| `station` | Start the station if it isn't running, and show it |
| `desktop` | Show the desktop (greetd's log-in screen, or the session behind it) |
| Tap the PS / Home button three times quickly | Toggle between the two |

Both stay running, so switching is a VT switch and nothing is lost on either
side. One or two presses of the PS button still reach RetroArch, which opens
its menu; three switch, so leaving a game that way leaves RetroArch's menu open
behind it. It isn't a hold, because holding PS is how a DualSense turns itself
off. Start+Select quits a game back to Pegasus.

The commands work for Jamie and for the arcade user without a password. Polkit
lets those two users start exactly three units, `arcade-switch@station`,
`arcade-switch@desktop` and `arcade-switch@toggle`, and nothing else; the
controller watcher, `arcade-hotkey`, is a root service that starts the third.

### What the TV shows after a boot

```nix
sessions.boot = "desktop";  # default: greetd on tty1, the station on demand
sessions.boot = "arcade";   # the station starts at boot and is shown
sessions.boot = "console";  # a text log-in on tty1, both on demand
```

## The TV and receiver

Picking up one of Irulan's input devices turns the TV on and puts the Denon on
CBL/SAT, Irulan's input, from the console, the desktop or the station alike:

- a key press, click or touch on the keyboard or trackpad, after five minutes
  without one
- a quick tap of a controller's PS button. Holding it doesn't count, so a
  controller can be switched off (PS held for about ten seconds) while the
  Apple TV has the receiver, without taking the input back
- a controller connecting

Putting them down puts the TV back in art mode, and the Denon follows it into
standby over CEC:

- Hyper+Escape on the keyboard (right ⌥ held, then Escape), anywhere
- TV Off in the desktop's power menu (Ctrl+Alt+Delete)
- every controller gone for 30 seconds while the station is on screen, whether
  switched off (hold PS for about ten seconds), flat or out of range, unless
  the Apple TV is playing something

After any of those but the last, the first key press or touch more than ten
seconds later turns the TV back on, without the five-minute wait.

The watcher is `av-input`, a root service. It runs `av on`, which starts Home
Assistant's `script.irulan_on_tv`. That wakes the Frame with Wake-on-LAN and
takes it out of art mode if it's off, then sends the Denon's CBL/SAT button
through the living room Broadlink, twice after a wake, because the Apple TV
wakes over CEC with the TV and takes the receiver's input a few seconds later.
For off it runs `av off`, which starts `script.irulan_off_tv`, or `av off
--automatic` for the controllers, which the script ignores while the Apple TV
plays. `av on`, `av off` and `av status` also work by hand, from any shell.

The CBL/SAT code is declared in that script, not learned, so there's nothing to
teach the Broadlink: it's the Denon RC-1253's, taken from a public infrared
database, and the comment beside it says how to make another button's the same
way.

There's no IR code for the Denon's standby to send instead of relying on CEC.
Its remote's power button toggles, and the discrete codes older Denons take do
nothing on this one.

## Where games go

Everything lives under `/srv/arcade`, owned by the `arcade` group with the
setgid bit set. Jamie is in that group, so files can be copied in over SSH
without becoming the arcade user.

```
/srv/arcade/
  roms/<system>/        games, plus metadata.pegasus.txt and media/ once scraped
  bios/                 BIOS files, flat (RetroArch's system directory)
  saves/  states/  screenshots/
```

| Directory | System | Core | Extensions |
|---|---|---|---|
| `megadrive` | Sega Genesis | Genesis Plus GX | md gen smd bin zip 7z |
| `mastersystem` | Sega Master System | Genesis Plus GX | sms zip 7z |
| `gamegear` | Sega Game Gear | Genesis Plus GX | gg zip 7z |
| `segacd` | Sega CD | Genesis Plus GX | chd cue iso m3u |
| `nes` | NES and Famicom Disk System | Mesen | nes fds zip 7z |
| `snes` | Super Nintendo | Snes9x | sfc smc zip 7z |
| `n64` | Nintendo 64 | Mupen64Plus-Next | n64 z64 v64 zip 7z |
| `gb` / `gbc` / `gba` | Game Boy, Color, Advance | mGBA | gb / gbc / gba, and zip |
| `psx` | PlayStation | SwanStation | chd cue pbp m3u |

The list, and each system's core, is `modules/nixos/arcade/systems.nix`.
Adding a system there creates its directory and its Pegasus collection.

Disc images: prefer `.chd`. A multi-disc game is an `.m3u` listing its discs,
which lets RetroArch swap them from its menu. Untested so far: whether Pegasus
also lists each disc as a game of its own. `.bin` is deliberately not an
extension for disc systems, since every `.cue` has one or more beside it.

### BIOS files

Put these in `/srv/arcade/bios`, named exactly as shown.

| System | Files | Needed? |
|---|---|---|
| PlayStation | `scph5500.bin` (Japan), `scph5501.bin` (US), `scph5502.bin` (Europe) | Yes, for the region's games |
| Sega CD | `bios_CD_U.bin`, `bios_CD_E.bin`, `bios_CD_J.bin` | Yes, for the region's games |
| Famicom Disk System | `disksys.rom` | Yes, for `.fds` |
| Game Boy Advance | `gba_bios.bin` | No; mGBA emulates it |
| Game Boy / Color | `gb_bios.bin`, `gbc_bios.bin` | No; only for the boot logo |

## Box art and descriptions

```sh
arcade-scrape            # every system with games in it
arcade-scrape snes n64   # just these
```

`arcade-scrape` runs Skyscraper against ScreenScraper and writes each
system's `metadata.pegasus.txt` and `media/` beside its games. Pegasus picks
the results up on its next start (`systemctl restart arcade-station`, or quit
Pegasus from its menu). Skyscraper's cache is in `~/.skyscraper`, so a rescrape
after adding games only fetches the new ones.

It doesn't fetch videos. The menu doesn't play them, and they would make up
most of a scrape's time and disk; `scrape.nix` says where to turn them on.

It reads a ScreenScraper account from 1Password at run time, through the
service account token in `~/.config/op/service-account-token`. Create this item
in the **Secrets** vault:

| Item | Field | Value |
|---|---|---|
| `ScreenScraper` | `username` | the screenscraper.fr account name |
| | `password` | its password |

The credentials go into a mode 600 file in `$XDG_RUNTIME_DIR` for the length
of the run, never onto a command line, the Nix store or this repo.

Each `metadata.pegasus.txt` opens with a header naming the collection and
its launch line. That header comes from Nix: `arcade-collections` rewrites it
at boot and on every switch, keeping the scraped games beneath it, and
`arcade-scrape` runs it again after Skyscraper has written its own.

## Controllers

Pair once, from a terminal on Irulan:

```sh
bluetoothctl
  scan on
  # DualSense / DualShock 4: hold Create (Share) and PS until the light flashes
  # 8BitDo: the pad's pairing mode, in its X-input or Switch mode
  pair <address>
  trust <address>
  connect <address>
```

After that, pressing PS wakes and reconnects the pad. The kernel's
`hid-playstation` driver handles the DualSense and DualShock 4,
`game-devices-udev-rules` gives the session on screen access to them, and both
RetroArch (by its autoconfig profiles) and Pegasus (through SDL) map them
without any configuration.

## Audio

RetroArch uses PipeWire's PulseAudio interface and follows the arcade user's
default output. Its driver and empty device override are declared in
`modules/nixos/arcade/default.nix`, overriding saved RetroArch settings. This
avoids passing a PulseAudio sink name to ALSA, which fails with `Unknown PCM`.

That default output is the receiver over HDMI, for every user on Irulan.
`hosts/irulan/default.nix` has WirePlumber prefer the sound card's HDMI
profile over its analog line-out, which otherwise wins and leaves no HDMI
output at all, and starts the HDMI route at full volume so the receiver is
the volume control. Analog only comes back while the receiver is off.

Output selection and volume belong to the `arcade` user's PipeWire session,
not Jamie's SSH session. To see what the station is playing into while it
runs:

```sh
sudo -u arcade XDG_RUNTIME_DIR=/run/user/$(id -u arcade) wpctl status
```

## The menu

The station's own Pegasus theme, `modules/nixos/arcade/theme/`, laid out like
the desktop shell's launcher: one glass card over the blurred wallpaper,
systems as capsules across the top, games as rows on the left, and the
selected game large on the right. A game with no art yet shows its initials
on a tile in its system's colour. Recent and Favorites appear as tabs once
they have anything in them.

| Button | Does |
|---|---|
| ↑ ↓ | Move through the games |
| ← → or L1 R1 | Previous or next system |
| L2 R2 | Back or forward a letter |
| ✕ | Play |
| △ | Favorite, or unfavorite |
| Start | Pegasus's own menu |

Its colours, fonts, corner radii, glass, spacing and springs come from
`modules/theme/palette.nix`, `fonts.nix` and `style.nix`, the same files the
desktop shell reads, so a change there reaches both. Only the station's own
choices sit in `theme/package.nix`: everything a quarter larger for the couch,
and how hard the backdrop is blurred.

gamescope blurs nothing, unlike Hyprland behind the shell, so the theme blurs
its own backdrop and each pane samples that by screen position. Anything that
sets `layer.enabled` above a pane breaks the lineup, which `ui/Pane.qml`
notes.

To try a change without switching, build the theme on its own and point a
throwaway Pegasus at it, inside a headless `cage` so nothing touches the TV:

```sh
nix build --impure --expr \
  '(import <nixpkgs> {}).callPackage ./modules/nixos/arcade/theme/package.nix {}'
```

Pegasus only loads a theme it finds under a `themes/` directory of its config,
named in `settings.txt` as `general.theme: themes/<name>/`, not by an
absolute path. Given anything else it falls back to its built-in grid theme
without saying why.

## First run on the machine

1. `nix-switch`, then check `systemctl status arcade-hotkey arcade-collections`.
2. Create the `ScreenScraper` item above.
3. Pair a controller, then `station`. Pegasus should appear with no
   collections until games are copied in.
4. Copy in a game and its BIOS if it needs one, restart the station, launch
   it, then try Start+Select and a triple tap of PS.
