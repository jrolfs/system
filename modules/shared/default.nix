{ ... }:

# System configuration every host gets, macOS and Linux alike. nix-darwin and
# NixOS spell these options the same way, so one module serves both.
{
  imports = [
    ./bootstrap.nix
    ./home-activation.nix
    ./home-backup.nix
    ./nix.nix
    ./packages.nix
    ./ssh.nix
  ];
}
