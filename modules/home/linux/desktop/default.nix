{ ... }:

# The user half of modules/nixos/desktop. Each module here is a no-op unless
# that one sets `desktop.enable`, so a headless NixOS host can import all of
# it unconditionally from linux.nix.

{
  imports = [
    ./hyprland.nix
    ./kanata-layers.nix
    ./lock.nix
    ./shell
    ./vicinae.nix
  ];
}
