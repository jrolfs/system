{ config, lib, pkgs, ... }:

# The compositor and what a session expects to find around it.

lib.mkIf config.desktop.enable {
  # uwsm runs Hyprland as a systemd user unit and starts graphical-session.target
  # around it, which is what every user service in modules/home/linux/desktop hangs
  # off. Without it those units would need their own way of learning that
  # Hyprland is up, and of stopping when it isn't.
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };

  # Hyprland's portal handles screen capture only. A file chooser comes from
  # the GTK portal, without which an "Open…" dialog in a sandboxed or portal-aware
  # app silently does nothing.
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # The shell's lock screen authenticates through this PAM service, named in
  # its PamContext. Its own service rather than borrowing `login` or `su`, so
  # what checks the password is declared here instead of inherited from
  # whatever those happen to stack up.
  security.pam.services.quickshell = { };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # home-manager writes GTK's dark-mode and font preferences through dconf,
  # which needs the system service to land anywhere.
  programs.dconf.enable = true;

  # File dialogs and file managers mount a USB drive or reach the trash by
  # asking udisks and gvfs over DBus, rather than doing it themselves.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
    grimblast
    playerctl
    wl-clipboard
  ];

  # Electron and Chromium apps otherwise come up under XWayland, blurry at
  # any fractional scale.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
