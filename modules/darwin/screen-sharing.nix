{ lib, ... }:

# Screen Sharing, so `vnc://<host>` from another Mac reaches this one.
#
# Only half of it is declarable. The System Settings toggle does two things:
#
# 1. Writes launchd's override database (/var/db/com.apple.xpc.launchd/
#    disabled.plist), flipping the `Disabled = true` that Apple ships in
#    com.apple.screensharing.plist. `launchctl enable` writes the same override,
#    and that is what activation does here.
# 2. Grants com.apple.screensharing.agent kTCCServiceScreenCapture and
#    kTCCServicePostEvent in the system TCC database. That database is SIP
#    protected, so root cannot write it and `tccutil` can only reset.
#
# With only the first half, Screen Sharing shows as on, the viewer
# authenticates, and then the connection fails with "Screen Sharing is not
# permitted on <host>". screensharingd logs the agent checking in with
# `screenCaptureFlag 0 postEventFlag 0`. The fix is a single off-and-on of the
# toggle per machine. The grants then persist, so activation only warns while
# they are missing.
#
# `enable` alone only takes effect at the next boot. `bootstrap` loads the job
# now, but errors if it is already loaded, and activation runs under `set -e`,
# hence the `print` guard. After the toggle the job is submitted by smd rather
# than loaded from the plist, which the guard treats as loaded.
#
# Reading the TCC database needs Full Disk Access in the terminal running the
# switch. Without it the query fails and the warning is skipped, rather than
# claiming grants are missing when they may not be.
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

    screenSharingGrants=$(/usr/bin/sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
      "select count(*) from access where client = 'com.apple.screensharing.agent' and auth_value = 2 and service in ('kTCCServiceScreenCapture', 'kTCCServicePostEvent')" \
      2>/dev/null || true)
    if [ -n "$screenSharingGrants" ] && [ "$screenSharingGrants" != 2 ]; then
      echo >&2 "screen sharing: not permitted to capture the screen yet; turn it off and on once in System Settings > General > Sharing"
    fi
  '';
}
