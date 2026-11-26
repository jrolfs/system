{ pkgs, lib, config, userName, ... }:

# Komodo bootstrap tier — core + mongo + periphery as
# virtualisation.oci-containers. These must exist before Komodo can
# manage anything else, so they live in nix-config (not in the compose
# repo that Komodo reads after it's up).
#
# Everything else Komodo eventually deploys (traefik, pi-hole, matter,
# the media stack on QNAP) is declared in the compose repo and
# orchestrated by Komodo via the docker socket on each periphery host.
#
# Migration: backup mongo data + komodo-keys volume from QNAP, restore
# into the new container volumes on Irulan after first systemd start.
# Update QNAP's periphery config to point at irulan.lan:9120 (or
# wherever Komodo core ends up reachable).

let
  # Host paths for persistent state. Bind-mounted into the containers.
  # /var/lib/komodo is created on first activation; mongo data, komodo
  # keys, and backups all live here.
  komodoStateDir = "/var/lib/komodo";

  # Komodo containers run as the same UID/GID the docker daemon uses;
  # since we're using virtualisation.docker (root daemon), default uids
  # inside the images work without ownership tweaks.
in
{
  systemd.tmpfiles.rules = [
    "d ${komodoStateDir} 0750 root root - -"
    "d ${komodoStateDir}/mongo-data 0750 root root - -"
    "d ${komodoStateDir}/mongo-config 0750 root root - -"
    "d ${komodoStateDir}/keys 0750 root root - -"
    "d ${komodoStateDir}/backups 0750 root root - -"
    "d ${komodoStateDir}/periphery-data 0750 root root - -"
  ];

  virtualisation.oci-containers = {
    backend = "docker";

    containers.komodo-mongo = {
      image = "mongo:4.4";
      autoStart = true;
      cmd = [ "--quiet" "--wiredTigerCacheSizeGB" "0.25" ];
      volumes = [
        "${komodoStateDir}/mongo-data:/data/db"
        "${komodoStateDir}/mongo-config:/data/configdb"
      ];
      # TODO(secrets): populate via a sops-nix or agenix secret, or via
      # `op read` if 1Password CLI is set up on Irulan. For first boot,
      # source from a manually-placed file at /etc/komodo/mongo.env.
      environmentFiles = [ "/etc/komodo/mongo.env" ];
      extraOptions = [ "--network=komodo" ];
    };

    containers.komodo-core = {
      image = "ghcr.io/moghtech/komodo-core:2";
      autoStart = true;
      dependsOn = [ "komodo-mongo" ];
      ports = [ "9120:9120" ];
      volumes = [
        "${komodoStateDir}/keys:/config/keys"
        "${komodoStateDir}/backups:/backups"
      ];
      environment = {
        KOMODO_DATABASE_ADDRESS = "komodo-mongo:27017";
      };
      environmentFiles = [
        "/etc/komodo/core.env"
      ];
      extraOptions = [ "--network=komodo" "--init" ];
    };

    containers.komodo-periphery = {
      image = "ghcr.io/moghtech/komodo-periphery:2";
      autoStart = true;
      dependsOn = [ "komodo-core" ];
      volumes = [
        "${komodoStateDir}/keys:/config/keys"
        "/var/run/docker.sock:/var/run/docker.sock"
        "/proc:/proc"
        "${komodoStateDir}/periphery-data:/share/Docker/Containers/komodo/data"
      ];
      environment = {
        PERIPHERY_ROOT_DIRECTORY = "/share/Docker/Containers/komodo/data";
      };
      environmentFiles = [
        "/etc/komodo/periphery.env"
      ];
      extraOptions = [ "--network=komodo" "--init" ];
    };
  };

  # The shared docker network all three Komodo containers attach to.
  # virtualisation.oci-containers doesn't manage networks itself, so
  # create it via a one-shot systemd unit that runs before any container.
  systemd.services.komodo-network = {
    description = "Create the komodo docker network";
    wantedBy = [ "multi-user.target" ];
    before = [
      "docker-komodo-mongo.service"
      "docker-komodo-core.service"
      "docker-komodo-periphery.service"
    ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.docker}/bin/docker network inspect komodo > /dev/null 2>&1 || \
        ${pkgs.docker}/bin/docker network create komodo
    '';
  };

  # Open Komodo core's port (9120) on the firewall so other peripheries
  # can reach it. Traefik (Komodo-deployed) will eventually proxy
  # https://komodo.rolfs.lan to localhost:9120, but until traefik is
  # up the dashboard is reachable at http://irulan.lan:9120 directly.
  networking.firewall.allowedTCPPorts = [ 9120 ];
}
