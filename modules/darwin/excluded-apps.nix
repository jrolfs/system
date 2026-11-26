# Per-host application exclusions — typically apps installed by organization
# device management. Keyed on the short hostname, and read by both
# homebrew.nix (casks) and mas.nix (App Store apps), which is why it lives
# here rather than in either of them.
#
# Names match the cask token or the App Store app name as written in those
# files, so an entry can cover both.

{
  # Xcode is a many-GB mas install; skip it during provisioning and add it
  # by hand (or drop this entry) when it's actually needed.
  ala = [];
  # Work machine, MDM-managed. Kandji installs 1Password and Zoom directly
  # into /Applications, and a cask refuses to clobber an app it doesn't own —
  # so the first switch failed on both. Note this excludes the 1Password
  # *GUI* only: `1password-cli` is a separate cask, is brew-managed here, and
  # is what `op` needs, so it stays.
  #
  # Xcode is no longer excluded here: kaset.nix builds Kaset from source on
  # this host, and that needs the Swift macro plugins and actool that only
  # ship inside Xcode.app.
  adrian = [ "1password" "zoom" ];
  newt = [ "Xcode" "zoom" ];
  orolo = [ "google-chrome" "Xcode" "zoom" ];
  yours-truly = [ "Xcode" ];
}
