{ pkgs, inputs, ... }:

# GUI applications for a NixOS host with a display attached.
#
# Imported per host rather than from modules/nixos/default.nix: a headless
# machine has no use for a terminal emulator or a browser, and these are heavy
# enough that inheriting them by default would be a tax on every future server.
#
# This is the Linux half of what Homebrew casks do on darwin. The apps below
# are the ones that earn their place on a machine that is used directly; plenty
# of other casks have Linux builds (audited: chromium, code-cursor, discord,
# figma-linux, firefox, google-chrome, obsidian, plex-desktop, plexamp,
# proxyman, signal-desktop, slack, spotify, telegram-desktop, yaak, zoom-us),
# so adding one is a line here rather than a research problem.
#
# What has no Linux equivalent at all, from that same audit: arq, chatgpt,
# daisydisk, linear, orbstack, raycast, and the macOS-only window and capture
# tools (moom, stay, cleanshot, hammerspoon, karabiner-elements). Most of that
# last group is answered by the compositor instead — window management and
# key remapping are Hyprland's job here, not an app's.

let
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  environment.systemPackages = [
    pkgs.kitty
    pkgs.zed-editor

    # Same browser as the Macs, from the flake that also supplies the
    # home-manager module in modules/home/browsers.nix. Glide publishes
    # x86_64-linux builds, so this is the identical binary story, not a
    # substitute.
    inputs.glide.packages.${system}.default
  ];

  # System-level rather than per-user so fontconfig sees them: an app started
  # by the compositor or a systemd unit isn't running inside the user's
  # home-manager profile.
  #
  # Mirrors the font-* casks on darwin. The Nerd Font packaging differs — nix
  # splits patched fonts into `nerd-fonts.<name>` where Homebrew ships one cask
  # per patched family — but the families are the same ones kitty and the
  # terminal config already name.
  fonts.packages = with pkgs; [
    atkinson-hyperlegible
    geist-font
    ibm-plex
    inter
    iosevka
    jetbrains-mono
    public-sans

    nerd-fonts.fira-code
    nerd-fonts.hack
    nerd-fonts.jetbrains-mono
  ];
}
