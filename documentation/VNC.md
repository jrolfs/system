# Physical desktop over VNC

WayVNC shares Jamie's existing Hyprland desktop on Irulan's TV (`HDMI-A-1`).
Remote input and clipboard changes affect that same session. There is no second
desktop, remote account, virtual monitor, or VM.
Viewer resizing is disabled so a Mac window cannot change the TV's display mode.

This does **not** capture the text console, greetd login screen, or gamescope
arcade session. Irulan still boots to the console. Start the desktop with
`desktop` and log in locally before connecting. Switching to the arcade does
not make it available over VNC, and Hyprland capture/input while its VT is
inactive should not be relied on. Log out to stop VNC entirely.

## Password and first switch

1. Add a concealed field named `vnc password` to `Secrets / Irulan` in
   1Password. Generate exactly eight ASCII letters or digits, and do not reuse
   the Linux login password. Traditional VNC authentication uses only eight
   bytes, even if a longer password is configured.
2. Ensure Irulan's existing 1Password service account can read that vault.
3. Build and switch Irulan to this configuration through the normal workflow.
   The system renders `/var/lib/onepassword/rendered/vnc-password`, owned by
   Jamie with mode `0400`. Only the reference is in the Nix store.
4. Log into Hyprland, then on the Mac run:

   ```bash
   open vnc://irulan:5900
   ```

   Use the dedicated VNC password when Screen Sharing prompts.

The user service starts with `graphical-session.target` and stops with it.
uwsm supplies the existing session's Wayland environment. Missing or malformed
credentials fail closed and retry every five seconds. The server never fetches
secrets itself, so retries do not consume 1Password requests.

To rotate the password, edit the field in 1Password, then run on Irulan:

```bash
sudo systemctl restart onepassword-render-vnc-password.service
systemctl --user restart wayvnc.service
```

The second restart is explicit because the renderer is a system service and
WayVNC is a user service. Existing connections are disconnected by the restart.
The renderer retains its last successful copy if 1Password is unreachable.

## Network boundary

TCP 5900 is allowed only on `enp3s0`, which carries the home LAN and connections
forwarded by the router's Tailscale subnet routing. Irulan does not run another
Tailscale client. Do not forward this port from the internet.

macOS Screen Sharing needs legacy VNC authentication. WayVNC therefore has
`enable_auth=true`, `relax_encryption=true`, and `allow_broken_crypto=true`.
This requires a password but **does not encrypt the session** and is vulnerable
to offline password guessing from captured handshakes. Treat the LAN as trusted.
Tailscale encrypts only the path to the router, not the final LAN hop.

For an encrypted connection all the way to Irulan, use an SSH tunnel instead:

```bash
ssh -N -L 5901:127.0.0.1:5900 irulan
open vnc://localhost:5901
```

## Checks

The credential/config wrapper has a local regression test, without a compositor
or VM:

```bash
python3 -m unittest discover -s modules/home/linux/desktop/tests -v
```

Run on Irulan as Jamie:

```bash
systemctl --user status wayvnc.service
journalctl --user -u wayvnc.service -b
wayvncctl output-list
```

After deployment, verify Mac authentication, the TV framebuffer, mouse and
keyboard input, reconnecting, and stopping the listener on logout. Input goes
directly into Hyprland through Wayland virtual input, bypassing kanata's
physical-keyboard remapping. Mac modifier behavior needs checking separately.

The abandoned independent-desktop work is preserved on `backup-vnc-headless`.
