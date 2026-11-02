{ pkgs, ... }:

let
  # A self-contained CLI to manage Sidecar (iPad-as-display) sessions by
  # driving the private SidecarCore.framework directly — no UI automation,
  # no AppleScript, no "Watch Me Do".  Connection state is read from the
  # framework itself (SidecarDisplayManager.connectedDevices), so `toggle`
  # and `status` are reliable without sniffing display names.
  #
  #   sidecar devices | connected
  #   sidecar list                       (attached external displays, tagged Wired/Sidecar)
  #   sidecar status     <name>
  #   sidecar connect    <name> [-wired]
  #   sidecar disconnect <name>
  #   sidecar toggle     <name> [-wired]
  #   sidecar arrange    <name> --arrange=<side>   (any external display, not just Sidecar)
  #
  # Compiled with the *system* Swift toolchain via xcrun: SidecarCore is an
  # Apple private framework that only exists in the macOS SDK, and the nix
  # sandbox is disabled on this host, so reaching the system toolchain here
  # is consistent with how icons.nix builds icon-setter.c with $CC.
  sidecar = pkgs.stdenv.mkDerivation {
    name = "sidecar";
    version = "1.0.0";
    dontUnpack = true;

    # nix's stdenv points DEVELOPER_DIR/SDKROOT at a nix-provided apple-sdk
    # that has no swiftc.  Clear DEVELOPER_DIR so xcode-select reports the
    # *real* persisted toolchain (Command Line Tools / Xcode), point xcrun at
    # it, and drop the nix SDKROOT so swiftc resolves the system macOS SDK.
    buildPhase = ''
      export DEVELOPER_DIR="$(/usr/bin/env -u DEVELOPER_DIR /usr/bin/xcode-select -p)"
      unset SDKROOT
      /usr/bin/xcrun --sdk macosx swiftc -O ${./pkgs/sidecar.swift} -o sidecar
    '';

    installPhase = ''
      mkdir -p $out/bin
      cp sidecar $out/bin/sidecar
    '';
  };
in
{
  environment.systemPackages = [ sidecar ];

  # The three toggles System Settings → Displays shows once an iPad is
  # connected, and the same three the menu bar Sidecar item flips. nix-darwin
  # has no structured option for them, but the domain is an ordinary
  # ~/Library/Preferences plist rather than a ByHost one, so
  # CustomUserPreferences reaches it.
  #
  # The key names are not guessable from the UI labels: SidecarUI and the
  # Displays settings extension both read `sidebarShown` (not showSidebar) and
  # `showTouchbar` (not showTouchBar, despite SidecarDisplayConfig spelling its
  # matching property showTouchBar). Nothing documents them; they were read out
  # of the binaries.
  #
  # Sidecar builds a SidecarDisplayConfig from these when a session starts, so a
  # change lands on the next connect, not on the running session.
  system.defaults.CustomUserPreferences."com.apple.sidecar.display" = {
    # The sidebar and the virtual Touch Bar are drawn on the iPad, eating a
    # strip of the only screen the session exists to provide.
    sidebarShown = false;
    showTouchbar = false;

    doubleTapEnabled = true;
  };
}
