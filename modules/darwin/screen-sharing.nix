{ lib, ... }:

# Screen Sharing, so `vnc://<host>` from another Mac reaches this one.
#
# There is no nix-darwin option and no preference key for it. The toggle in
# System Settings writes launchd's own override database
# (/var/db/com.apple.xpc.launchd/disabled.plist), flipping the `Disabled = true`
# that Apple ships in com.apple.screensharing.plist. `launchctl enable` writes
# that same override, so this is what the toggle does, and it survives reboots.
#
# `enable` alone only takes effect at the next boot. `bootstrap` loads the job
# now, but errors if it is already loaded, and activation runs under `set -e`,
# hence the `print` guard. The job is socket-activated, so once it is loaded,
# screensharingd only runs while a client is connected.
#
# This is Screen Sharing, not Remote Management. The ARD `kickstart` route can
# no longer grant screen control without MDM, and System Settings treats the
# two as mutually exclusive.
#
# Who may connect is the com.apple.access_screensharing group, which macOS
# creates with the admin group nested in it. That is left alone, so admin
# accounts authenticate with their own passwords. The legacy "VNC viewers may
# control screen with password" setting for third-party clients stays off: it
# stores a reversibly obfuscated password in /Library/Preferences.

{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /bin/launchctl enable system/com.apple.screensharing
    if ! /bin/launchctl print system/com.apple.screensharing >/dev/null 2>&1; then
      /bin/launchctl bootstrap system /System/Library/LaunchDaemons/com.apple.screensharing.plist
    fi
  '';
}
