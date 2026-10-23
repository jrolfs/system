{ ... }:

# System configuration every host gets, macOS and Linux alike. nix-darwin and
# NixOS spell these options the same way, so one module serves both.
{
  imports = [
    ./bootstrap.nix
    ./home-backup.nix
    ./packages.nix
  ];
}
