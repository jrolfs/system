{ pkgs, lib, ... }:

# iCloud Keychain stays off (1Password) and ~/Documents stays a plain local
# directory (Resilio syncs it). Neither is a preference: the dataclass flags in
# MobileMeAccounts.plist mirror server-side account state, so writing them does
# nothing — the only local lever is a configuration profile carrying
# com.apple.applicationaccess restrictions.
#
# allowCloudDesktopAndDocuments kills only the Desktop & Documents redirection;
# iCloud Drive itself is left alone (allowCloudDocumentSync would take out the
# whole thing).
#
# `profiles` on macOS 26 has no install verb, so the profile can be built here
# but not installed: a human approves it once per machine in System Settings →
# General → Device Management — the same class of one-time step as the
# icon-customizer FDA grant. Activation below nags with the exact command until
# that's happened. Installation is detectable because the payload lands in the
# managed-preferences layer, which `defaults read` includes.

let
  profile = pkgs.writeText "icloud-restrictions.mobileconfig" # xml
    ''
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>PayloadContent</key>
        <array>
          <dict>
            <key>PayloadType</key>
            <string>com.apple.applicationaccess</string>
            <key>PayloadIdentifier</key>
            <string>com.jrolfs.icloud.applicationaccess</string>
            <key>PayloadUUID</key>
            <string>B0E56D2C-1F3A-4C4B-9C4E-8A2D5E7F1A23</string>
            <key>PayloadDisplayName</key>
            <string>iCloud restrictions</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>allowCloudKeychainSync</key>
            <false/>
            <key>allowCloudDesktopAndDocuments</key>
            <false/>
          </dict>
        </array>
        <key>PayloadType</key>
        <string>Configuration</string>
        <key>PayloadScope</key>
        <string>User</string>
        <key>PayloadIdentifier</key>
        <string>com.jrolfs.icloud</string>
        <key>PayloadUUID</key>
        <string>4D7A9F31-6B2E-4E8A-A1C5-3F9B0D6C8E42</string>
        <key>PayloadDisplayName</key>
        <string>iCloud restrictions (1Password, Resilio)</string>
        <key>PayloadDescription</key>
        <string>Disables iCloud Keychain and the Desktop &amp; Documents redirection; iCloud Drive is unaffected.</string>
        <key>PayloadVersion</key>
        <integer>1</integer>
      </dict>
      </plist>
    '';
in
{
  home.activation.icloudProfile = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      keychain=$(/usr/bin/defaults read com.apple.applicationaccess allowCloudKeychainSync 2>/dev/null || echo missing)
      documents=$(/usr/bin/defaults read com.apple.applicationaccess allowCloudDesktopAndDocuments 2>/dev/null || echo missing)

      if [ "$keychain" != 0 ] || [ "$documents" != 0 ]; then
        warnEcho "icloud: restrictions profile not installed — run 'open ${profile}' and approve it in System Settings → General → Device Management"
      fi
    '';
}
