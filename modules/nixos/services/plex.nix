{ pkgs, lib, ... }:

# Plex Media Server native NixOS module. Migrated from a bare-metal
# install on QNAP. Media stays on the NAS (mounted at /mnt/nas/media,
# declared in hosts/irulan/default.nix); library DB + transcode cache
# live on the local SSD at services.plex.dataDir.
#
# Migration: stop Plex on QNAP, rsync /share/Docker/Containers/plex/config
# (or wherever the QNAP install's "Plex Media Server" support dir is)
# to /var/lib/plex/Library/Application Support/Plex Media Server/. Start
# plex.service on Irulan; library is fully populated with watch state,
# collections, metadata.
#
# Hardware transcoding via Intel Quick Sync requires:
#  - hardware.graphics.enable + intel-media-driver (set in hosts/irulan/)
#  - plex user in video + render groups (NixOS module does this when
#    `services.plex.openFirewall = true` and the user is created)
#  - Plex Pass (the "Use hardware acceleration when available" toggle
#    in Plex Settings → Transcoder is per-user and lives in the DB,
#    so it survives the rsync)

{
  services.plex = {
    enable = true;
    openFirewall = true;
    # dataDir defaults to /var/lib/plex. The migration target is this path.
    # dataDir = "/var/lib/plex";
    # user / group default to "plex". The NixOS module creates the user.
  };
}
