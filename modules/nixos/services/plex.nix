{ lib, pkgs, ... }:

# Plex Media Server, native rather than in Docker.
#
# This is the server that ran as a QPKG on Leia, moved here with its library,
# watch state and identity in phase 3 of documentation/IRULAN-MIGRATION.md. It
# reads the same media over NFS (hosts/irulan/default.nix mounts it read-only),
# and the library database and transcode cache stay on the local SSD under
# dataDir.
#
# Hardware transcoding needs Plex Pass, the "Use hardware acceleration when
# available" setting, and access to /dev/dri. The module's default
# accelerationDevices already lets the unit see every device; the groups below
# grant the permission on the render node itself.

let
  # Leia's Plex was on this build when its library moved here, and Plex's
  # database only migrates forward, so Irulan can't run anything older on that
  # data. nixpkgs was still on 1.43.5.11029 at the time, even on master. The
  # override applies only while nixpkgs is behind it, so it lapses on its own
  # after an update and can then be deleted.
  minimum = {
    version = "1.43.5.11079-b3b13e506";
    sha256 = "01m2hwngl54nfq7gjiplkpp3in0z2iwq4ff4bj96wvg0jwfagsbl";
  };

  plex =
    if lib.versionOlder pkgs.plexRaw.version minimum.version then
      pkgs.plex.override {
        plexRaw = pkgs.plexRaw.overrideAttrs {
          inherit (minimum) version;
          src = pkgs.fetchurl {
            url = "https://downloads.plex.tv/plex-media-server-new/${minimum.version}/debian/plexmediaserver_${minimum.version}_amd64.deb";
            inherit (minimum) sha256;
          };
        };
      }
    else
      pkgs.plex;
in
{
  services.plex = {
    enable = true;
    package = plex;
    # 32400 for clients, plus the GDM discovery ports that let apps on the LAN
    # find the server without going through plex.tv.
    openFirewall = true;
  };

  users.users.plex.extraGroups = [ "render" "video" ];
}
