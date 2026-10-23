{ pkgs, lib, config, ... }:

# The desktop picture.
#
# The image files sync themselves: ~/Images is a Resilio share, and
# ~/Images/Wallpapers is the library inside it. What was never synced is the
# *choice* — a machine with the entire library still had to be told which
# picture to use, by hand, in System Settings. That is what this declares.
#
# It cannot be declared as a preference. macOS keeps the answer in
# ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist, and
# WallpaperAgent owns that file rather than reading it: writing the new picture
# in by hand changes nothing on screen, and the agent overwrites the file from
# its own state the next time Dock restarts. Measured on macOS 26.
#
# So the picture is set through NSWorkspace, the only public way in, and the
# work of doing that lives in Hammerspoon — see
# dotfiles/home/.hammerspoon/modules/wallpaper.lua. Hammerspoon is already the
# place this config keeps the macOS APIs that have no declarative surface, it
# exposes NSWorkspace as hs.screen:desktopImageURL, and it is the only thing
# here that can see the other spaces at all — which is how the picture reaches
# more than the one space that happens to be active, without a switch ever
# taking the screen to do it.

let
  wallpaper = "${config.home.homeDirectory}/Images/Wallpapers/BLACK/BLACK II - Gruvbox Material.png";

  # Hammerspoon's CLI. It ships inside the cask; $(brew --prefix)/bin/hs is only
  # a symlink Hammerspoon offers to create, so it can't be relied on.
  hs = "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs";

  # `require` caches, and home-manager has just relinked the module, so a
  # Hammerspoon that has applied a wallpaper on an earlier switch would
  # otherwise go on running the copy it loaded then.
  call = # lua
    ''
      package.loaded["modules.wallpaper"] = nil
      local ok, wallpaper = pcall(require, "modules.wallpaper")
      if not ok then return "wallpaper:unavailable" end
      return "wallpaper:" .. wallpaper.apply("${wallpaper}")
    '';

  apply = pkgs.writeShellScript "wallpaper-apply" ''
    set -uo pipefail

    if [ ! -x ${hs} ]; then
      echo "wallpaper: Hammerspoon is not installed yet, leaving the desktop alone" >&2
      exit 0
    fi

    # Answers are sentinel-prefixed and matched loosely because `hs -c`
    # interleaves its own "-- Loading extension: fs" lines on the first call
    # after Hammerspoon starts. The timeout is because this call is what a
    # switch waits on, and a Hammerspoon whose main thread is wedged would
    # otherwise hold the whole activation open.
    result=$(${pkgs.coreutils}/bin/timeout 20 ${hs} -c ${lib.escapeShellArg call} 2>/dev/null)

    case "$result" in
      *wallpaper:unchanged*)
        ;;
      # Only the space in front of you. The others are painted as you arrive at
      # them, because the alternative is Mission Control taking the screen in
      # the middle of a switch.
      *wallpaper:set*)
        echo "wallpaper: ${builtins.baseNameOf wallpaper}, and the other spaces as you visit them" >&2
        ;;
      *wallpaper:missing*)
        echo "wallpaper: ${wallpaper} has not synced yet, leaving the desktop alone" >&2
        ;;
      *wallpaper:unavailable*)
        echo "wallpaper: Hammerspoon has no wallpaper module — reload its config" >&2
        ;;
      *)
        echo "wallpaper: no answer from Hammerspoon, so the desktop is untouched" >&2
        ;;
    esac

    exit 0
  '';
in
{
  home.activation.wallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${apply} \
        || warnEcho "wallpaper: could not set the desktop picture — see the Hammerspoon console"
    '';
}
