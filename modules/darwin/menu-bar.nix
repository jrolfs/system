{ config, lib, pkgs, ... }:

# Apps kept out of the menu bar by System Settings' "Allow in the Menu Bar".
#
# macOS 26 added that switch alongside the older per-item `NSStatusItem
# VisibleCC` keys defaults.nix pins, and it is not one of them. Turning it off
# writes nothing to the app's own domain. Control Center records it instead,
# in `trackedApplications` in its group container: a binary plist stored as a
# `data` value, holding a flat array that alternates an app's key and its
# record, which is how Swift encodes a dictionary whose keys are not strings.
# CustomUserPreferences can only replace that blob whole, which would also
# throw away every other app's setting, so this edits the entries in place.
#
# The group container is protected by TCC, so activation's `sudo --user`
# cannot read it, let alone write it, and this goes through fda.nix's shim.
# The write still goes through `defaults` rather than editing the file, so
# cfprefsd's cached copy is the one that changes. ControlCenter only reads the
# list at launch, hence the restart, which is skipped when nothing changed.
#
# An app Control Center has never seen gets a record added ahead of time, so
# its item never appears at all. Any other app keeps whatever was set by hand.

let
  hiddenApps = config.local.menuBar.hiddenApps;

  domain = "/Users/${config.system.primaryUser}/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter";

  apply = pkgs.writeShellScriptBin "menu-bar-hidden-apps" # bash
    ''
      set -euo pipefail

      domain=${lib.escapeShellArg domain}
      jq=${lib.getExe pkgs.jq}

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      # Absent on a machine where Control Center has yet to track anything,
      # and then the list starts empty.
      if plutil -extract trackedApplications raw -o - "$domain.plist" 2>/dev/null \
        | base64 -d > "$work/current.plist" 2>/dev/null \
        && [ -s "$work/current.plist" ]
      then
        plutil -convert json -o "$work/current.json" "$work/current.plist"
      else
        echo '[]' > "$work/current.json"
      fi

      # menuItemLocations names whichever bundle owns the status item, which
      # can be a helper (Fantastical's is). A new record assumes the app owns
      # its own, so an app whose item comes from a helper wants listing only
      # once Control Center has a record for it.
      "$jq" -c --argjson hidden ${lib.escapeShellArg (builtins.toJSON hiddenApps)} '
        reduce $hidden[] as $id (.;
          {bundle: {_0: $id}} as $key
          | ([range(0; length; 2) as $i | select(.[$i] == $key) | $i] | first) as $at
          | if $at == null then
              . + [$key, {isAllowed: false, location: $key, menuItemLocations: [$key]}]
            else
              .[$at + 1].isAllowed = false
            end)
      ' "$work/current.json" > "$work/desired.json"

      if [ "$("$jq" -c . "$work/current.json")" = "$(cat "$work/desired.json")" ]; then
        exit 0
      fi

      plutil -convert binary1 -o "$work/desired.plist" "$work/desired.json"
      defaults write "$domain" trackedApplications \
        -data "$(xxd -p "$work/desired.plist" | tr -d '\n')"
      echo "menu-bar: kept out of the menu bar: ${lib.concatStringsSep ", " hiddenApps}"

      # launchd relaunches it straight away.
      killall ControlCenter 2>/dev/null || true
    '';
in
{
  options.local.menuBar.hiddenApps = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "com.tinyspeck.slackmacgap" ];
    description = ''
      Bundle identifiers of apps whose "Allow in the Menu Bar" switch in
      System Settings is kept off. Switching one back on there lasts only
      until the next run puts it back, which happens as soon as Control Center
      records the change.
    '';
  };

  config = lib.mkIf (hiddenApps != [ ]) {
    fda.operations.menu-bar-hidden-apps = apply;

    # The watch is what makes this stick. Control Center rewrites the file
    # when the switch is flipped in System Settings and when it first sees an
    # app, and either can turn an app back on. The run triggered by this
    # agent's own write finds nothing to change and exits.
    launchd.user.agents.menu-bar-hidden-apps = {
      serviceConfig = {
        ProgramArguments = [ config.fda.runPath "menu-bar-hidden-apps" ];
        RunAtLoad = true;
        WatchPaths = [ "${domain}.plist" ];
      };
    };
  };
}
