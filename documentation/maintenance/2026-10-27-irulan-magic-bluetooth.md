# Magic Keyboard and Trackpad over Bluetooth on Irulan

**Hosts:** irulan (adrian lent a hand) · **Fixed in:** `5f10b10e`, plus a
one-time re-pairing

## Summary

The Magic Keyboard and Magic Trackpad only worked on Irulan over USB. Unplugged,
neither connected. Three things were in the way, and only one of them was
configuration. The keyboard's pairing on Irulan had never finished, both
devices still remembered some other host and so never advertised, and nothing
at the text console could answer a pairing request. Both now pair and reconnect
over Bluetooth at the console with no agent running. They come back by
themselves after a power cycle.

## Timeline

- **Oct 22:** the keyboard tried to connect and bluetoothd turned it away with
  `Rejected connection from !bonded device`. From then on Irulan retried it
  every minute and got `Host is down`, until Oct 27.
- **Oct 27:** both devices unplugged and power cycled. Neither showed up in a
  scan, and a direct connection to the keyboard's address timed out.
- **Oct 27:** each was plugged into adrian, unplugged, and forgotten there with
  `blueutil --unpair`. Both advertised straight away, and Irulan paired, trusted
  and connected them.
- **Oct 27:** with no agent running, both were switched off and on. Both
  reconnected within seconds, and kanata registered the keyboard without being
  restarted.

## Root causes

1. **On a cable they're USB devices.** A Magic Keyboard or Trackpad on USB stops
   using Bluetooth altogether. macOS pairs them over the cable as well, but Linux
   can't (BlueZ's `CablePairing` covers Sony pads, not Apple's), so plugging into
   Irulan charges them and does nothing for the pairing.
2. **Each one remembers a single host and won't advertise while it does.** Neither
   ala nor adrian had them, but power cycling still didn't make them
   discoverable. Whatever they had paired with last (the names "Teclado" and
   "Ratón Plano" suggest a Spanish-language Apple device), they kept trying that
   host instead.
3. **No pairing agent at the console.** bluetoothd only accepts pairing while an
   agent is registered, and the only agent was blueman's applet in the Hyprland
   session. With Irulan booting to the console, the adapter reported
   `Pairable: no`.
4. **The configuration depended on the desktop.** The adapter's settings and
   `hid_apple` were behind `desktop.enable`. Bluetooth only kept working at the
   console because `arcade.enable` happened to carry a second copy.

## What we did

- **`5f10b10e`:** the adapter's settings moved to `modules/nixos/bluetooth.nix`,
  which applies wherever `hardware.bluetooth.enable` is set. Irulan sets it
  directly. `hid_apple fnmode=1` moved to `modules/nixos/keyboard`. The desktop
  keeps blueman and libinput, and the arcade drops its copy. Built on Irulan,
  the generated `main.conf` and modprobe options are identical to what was
  running before.
- **Pairing, by hand:** described under "Next time" below. The bonds are in
  `/var/lib/bluetooth`, outside the Nix store, so they survive switches and
  reboots but not a reinstall.

## Still to do

- **Fn on the keyboard.** Over USB the kernel logged `Fn key not found (Apple
  Wireless Keyboard clone?), disabling Fn key handling`, which would make
  `fnmode` moot. Check whether Fn and the media keys behave over Bluetooth.
- **Device names.** They still call themselves "Teclado" and "Ratón Plano".
  `bluetoothctl set-alias` would fix that, though only in Irulan's own
  `/var/lib/bluetooth`.
- **Pairing from the desktop.** Not tried with blueman since this change.

## Next time

Pairing a Magic Keyboard or Trackpad with Irulan, or any Linux host:

1. If it won't show up in `bluetoothctl scan on`, it remembers another host.
   Plug it into a Mac, unplug it, and choose Forget This Device there (or
   `nix run nixpkgs#blueutil -- --unpair <address>`). It advertises right away.
2. On Irulan, at the console or over SSH, run `bluetoothctl`. Then `scan on`,
   `pair <address>` (answer `yes` to the passkey confirmation), `trust
   <address>`, `connect <address>`. If `connect` reports
   `br-connection-create-socket`, press a key. Apple keyboards prefer to start
   the reconnection themselves.
3. Don't plug it into a Mac afterwards. That pairs it to the Mac again, and step
   1 has to be repeated.
4. To drive `bluetoothctl` from a script, don't pipe answers into its prompts.
   They arrive late or not at all. Run `bt-agent -c NoInputNoOutput` (from
   `bluez-tools`) as the agent and give each step as a one-shot `bluetoothctl`
   command.
