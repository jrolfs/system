{ lib, ... }:

# Energy settings, per power source.
#
# nix-darwin's `power.sleep` and `networking.wakeOnLan` go through
# `systemsetup`, which writes AC and battery at once. The settings that matter
# on a laptop are the ones that differ between the two: never sleep on the
# adapter but do on battery, which is System Settings' "Prevent automatic
# sleeping on power adapter when the display is off". `pmset -b` and `-c`
# address each source on its own, so everything goes through it here.
#
# `womp` on battery is the "Always" choice of "Wake for network access". Left
# at "Only on Power Adapter", a magic packet does nothing while the Mac is
# unplugged, which looks exactly like Wake-on-LAN being broken. Even with it
# on, a Wi-Fi-only Mac in deep sleep is woken reliably by a Bonjour Sleep
# Proxy (an Apple TV or HomePod on the network), not by a raw packet.
#
# "Optimize video streaming while on battery" is not a pmset setting, and no
# preference file records it while it is off, so it stays a manual toggle.

let
  shared = {
    displaysleep = 45;
    disksleep = 10;
    womp = 1;
  };

  bySource = {
    c = shared // { sleep = 0; };
    b = shared // { sleep = 1; lessbright = 1; };
  };

  pmsetArguments = lib.concatStringsSep " " (
    lib.mapAttrsToList (
      source: settings:
      "-${source} " + lib.concatStringsSep " " (lib.mapAttrsToList (key: value: "${key} ${toString value}") settings)
    ) bySource
  );
in

{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    /usr/bin/pmset ${pmsetArguments}
  '';
}
