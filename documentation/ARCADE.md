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
| Hold the PS / Home button for about a second | Toggle between the two |

Both stay running, so switching is a VT switch and nothing is lost on either
side. A short press of the PS button still reaches RetroArch, which opens its
menu. Start+Select quits a game back to Pegasus.

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

## Box art, videos and descriptions

```sh
arcade-scrape            # every system with games in it
arcade-scrape snes n64   # just these
```

`arcade-scrape` runs Skyscraper against ScreenScraper and writes each
system's `metadata.pegasus.txt` and `media/` beside its games. Pegasus picks
the results up on its next start (`systemctl restart arcade-station`, or quit
Pegasus from its menu). Skyscraper's cache is in `~/.skyscraper`, so a rescrape
after adding games only fetches the new ones.

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

## The theme

Pegasus's default theme, pegasus-theme-grid, recolored from
`modules/theme/palette.nix` and set in Geist from `modules/theme/fonts.nix`.
Its corner radius and opacities sit in one generated `Style.qml`, from the
`style` set in `modules/nixos/arcade/pegasus.nix`. The theme has no monospace
text, so JetBrains Mono has nowhere to go.

## First run on the machine

1. `nix-switch`, then check `systemctl status arcade-hotkey arcade-collections`.
2. Create the `ScreenScraper` item above.
3. Pair a controller, then `station`. Pegasus should appear with no
   collections until games are copied in.
4. Copy in a game and its BIOS if it needs one, restart the station, launch
   it, then try Start+Select and holding PS.
