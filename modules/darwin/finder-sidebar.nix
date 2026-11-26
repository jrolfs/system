{ pkgs, lib, config, userName, ... }:

# Finder's sidebar Favorites.
#
# Not a preference. The list lives in
# `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.FavoriteItems.sfl4`,
# an NSKeyedArchiver graph whose entries are security-scoped bookmark blobs
# carrying the volume UUID and inode of each target. So the file cannot be
# copied between machines the way a plist can — the same folder on two Macs
# has two different bookmarks — which is why this declares *paths* and lets
# the machine mint its own.
#
# `mysides` (overlaid, built from source — see overlays/default.nix) drives
# LSSharedFileList, deprecated since 10.11 and still the only writable route:
# `sfltool` has list/clear/reset and no verb that adds an item.
#
# Ordering is why the reconcile is all-or-nothing. `mysides add` appends, so
# there is no way to insert at a position; getting a declared order means
# clearing the list and adding in sequence. That's cheap and invisible, but it
# does mean a hand-added favourite disappears on the next switch, which is the
# point of declaring it.

let
  sidebar = config.local.finder.sidebar;
  home = "/Users/${userName}";

  # `mysides list` prints `Name -> file:///path/`, which is what the reconcile
  # compares against. Built here so the comparison and the writes can't
  # disagree about trailing slashes.
  expected = lib.concatMapStringsSep "\n"
    ({ name, path }: "${name} -> file://${path}/")
    sidebar;

  reconcile = pkgs.writeShellScript "finder-sidebar" ''
    set -uo pipefail

    mysides=${lib.getExe pkgs.mysides}

    current=$("$mysides" list 2>/dev/null || true)

    if [ "$current" = ${lib.escapeShellArg expected} ]; then
      exit 0
    fi

    echo "finder: reconciling sidebar favourites"

    # Remove by name, reading the *current* list rather than the declared one:
    # anything added by hand has to go too, or the add below lands after it and
    # the order comes out wrong.
    printf '%s\n' "$current" | while IFS= read -r line; do
      [ -n "$line" ] || continue
      "$mysides" remove "''${line%% -> *}" >/dev/null 2>&1 || true
    done

    ${lib.concatMapStringsSep "\n"
      ({ name, path }: ''
        "$mysides" add ${lib.escapeShellArg name} ${lib.escapeShellArg "file://${path}/"} \
          || echo >&2 "finder: could not add ${name} (${path})"
      '')
      sidebar}
  '';
in
{
  options.local.finder.sidebar = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Label shown in the sidebar.";
        };
        path = lib.mkOption {
          type = lib.types.str;
          description = "Absolute path, no trailing slash.";
        };
      };
    });
    default = [ ];
    description = ''
      Finder sidebar favourites, in order. Replaces whatever is there —
      `mysides` can only append, so the list is rebuilt rather than merged.
    '';
  };

  config = {
    # Carried from newt, which had accumulated the useful set. Desktop,
    # Documents, Downloads, Applications and home are macOS's own defaults;
    # the rest are the ones worth having back on a new machine.
    local.finder.sidebar = lib.mkDefault [
      { name = "Developer"; path = "${home}/Developer"; }
      { name = "Documents"; path = "${home}/Documents"; }
      { name = "Pictures"; path = "${home}/Pictures"; }
      { name = "Images"; path = "${home}/Images"; }
      { name = "Sync"; path = "${home}/Sync"; }
      { name = "Applications"; path = "/Applications"; }
      { name = "Desktop"; path = "${home}/Desktop"; }
      { name = "Screenshots"; path = "${home}/Images/Screenshots"; }
      { name = "Downloads"; path = "${home}/Downloads"; }
      { name = userName; path = home; }
    ];

    environment.systemPackages = [ pkgs.mysides ];

    # As the user, not root: the sidebar is per-user state under ~/Library,
    # and LSSharedFileList writes wherever HOME points.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "finder sidebar..." >&2
      sudo --user=${userName} -- ${reconcile} || \
        echo >&2 "finder: sidebar reconcile failed"
    '';
  };
}
