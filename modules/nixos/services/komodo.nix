{ pkgs, lib, config, hostname, ... }:

# Komodo, split into its two halves so a host can run either one.
#
# Every machine that Komodo deploys stacks to runs a Periphery, and exactly one
# machine runs Core. Core moves from Leia to Irulan ahead of the services
# (documentation/KOMODO-CORE-CUTOVER.md), so Irulan runs both halves and Leia
# keeps only its periphery.
#
# The periphery is nixpkgs' native systemd module rather than the container
# Leia runs. Komodo recommends systemd for it, and a containerised periphery
# has to see stack directories at the same path the host's docker daemon does,
# which is why Leia's is mounted at a mirrored /share/Docker/... path.

let
  cfg = config.komodo;

  coreStateDir = "/var/lib/komodo";
  coreKey = "${coreStateDir}/keys/core.key";

  # Core is live on this host: enabled, and switched on after the cutover.
  coreActive = cfg.core.enable && cfg.core.activate;

  # `Secretes` is the section's actual label in the item, typo included.
  item = "op://Secrets/Komodo/Secretes";

  mongoEnvironment = pkgs.writeText "komodo-mongo.env.tpl" ''
    MONGO_INITDB_ROOT_USERNAME={{ ${item}/mongo username }}
    MONGO_INITDB_ROOT_PASSWORD={{ ${item}/mongo password }}
  '';

  coreEnvironment = pkgs.writeText "komodo-core.env.tpl" ''
    KOMODO_DATABASE_USERNAME={{ ${item}/mongo username }}
    KOMODO_DATABASE_PASSWORD={{ ${item}/mongo password }}
    KOMODO_JWT_SECRET={{ ${item}/jwt secret }}
    KOMODO_WEBHOOK_SECRET={{ ${item}/webhook secret }}
  '';
in
{
  options.komodo = {
    core = {
      enable = lib.mkEnableOption ''
        Komodo Core and its MongoDB as containers, with their credentials
        rendered from the `Komodo` item in 1Password. Mongo starts right away;
        Core waits for `komodo.core.activate`
      '';

      activate = lib.mkEnableOption ''
        starting Core. Off until a database and key pair have been carried over
        from the Core this one replaces, since a Core started without them
        generates a new key pair (which every pinned periphery then rejects)
        and an empty database
      '';

      imageTag = lib.mkOption {
        type = lib.types.str;
        default = "2";
        description = ''
          Tag of `ghcr.io/moghtech/komodo-core`. Pin it to the exact release
          the database comes from before restoring it, and keep it at or above
          every periphery's version.
        '';
      };
    };

    periphery = {
      enable = lib.mkEnableOption "the Komodo Periphery agent, connecting out to Core";

      coreAddress = lib.mkOption {
        type = lib.types.str;
        # Straight to the Core beside it when there is one, so this host stays
        # manageable while Leia, and the Traefik on it, are down.
        default = if coreActive then "ws://127.0.0.1:9120" else "https://komodo.rolfs.casa";
        defaultText = lib.literalMD ''
          `ws://127.0.0.1:9120` when this host runs Core, otherwise
          `https://komodo.rolfs.casa`
        '';
        description = ''
          Where Core is reachable from this host. The periphery dials out to it
          over a websocket, so nothing on this host listens for Core.
        '';
      };

      connectAs = lib.mkOption {
        type = lib.types.str;
        default = hostname;
        description = "The Server name this host appears as in Komodo.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.periphery.enable {
      # No onboarding key: the periphery generates its own key pair under
      # /var/lib/komodo-periphery/keys on first start, and Core records the
      # public half of an unrecognised connection as the server's attempted
      # key, to be accepted once in the UI. Nothing secret enters this config.
      # With an outbound core address the inbound server is off, so no port
      # is opened either.
      services.komodo-periphery = {
        enable = true;
        outbound = {
          inherit (cfg.periphery) coreAddress connectAs;
        };
      };
    })

    (lib.mkIf cfg.core.enable {
      systemd.tmpfiles.rules = [
        "d ${coreStateDir} 0750 root root - -"
        "d ${coreStateDir}/mongo-data 0750 root root - -"
        "d ${coreStateDir}/mongo-config 0750 root root - -"
        "d ${coreStateDir}/keys 0750 root root - -"
        "d ${coreStateDir}/backups 0750 root root - -"
      ];

      onepassword.templates = {
        komodo-mongo = {
          template = mongoEnvironment;
          consumers = [ "docker-komodo-mongo" ];
        };

        # Core is only a consumer once it's meant to run: a consumer is
        # restarted whenever its template is rendered again, which would
        # otherwise start Core before the cutover.
        komodo-core = {
          template = coreEnvironment;
          consumers = lib.optional cfg.core.activate "docker-komodo-core";
        };
      };

      virtualisation.oci-containers = {
        backend = "docker";

        # Started before Core so the database can be restored into it. An empty
        # Mongo initialises its root user from these credentials, which are the
        # ones the restored database was dumped with.
        containers.komodo-mongo = {
          image = "mongo:4.4";
          autoStart = true;
          cmd = [ "--quiet" "--wiredTigerCacheSizeGB" "0.25" ];
          volumes = [
            "${coreStateDir}/mongo-data:/data/db"
            "${coreStateDir}/mongo-config:/data/configdb"
          ];
          environmentFiles = [ config.onepassword.templates.komodo-mongo.path ];
          extraOptions = [ "--network=komodo" ];
        };

        containers.komodo-core = {
          image = "ghcr.io/moghtech/komodo-core:${cfg.core.imageTag}";
          autoStart = cfg.core.activate;
          dependsOn = [ "komodo-mongo" ];
          ports = [ "9120:9120" ];
          volumes = [
            "${coreStateDir}/keys:/config/keys"
            "${coreStateDir}/backups:/backups"
          ];
          # The non-secret half of Leia's komodo.env. FIRST_SERVER_NAME and
          # the initial admin are left out: both apply only to an empty
          # database, and this one is restored.
          environment = {
            TZ = config.time.timeZone;
            KOMODO_DATABASE_ADDRESS = "komodo-mongo:27017";
            KOMODO_HOST = "https://komodo.rolfs.casa";
            KOMODO_TITLE = "Komodo";
            KOMODO_LOCAL_AUTH = "true";
            KOMODO_DISABLE_CONFIRM_DIALOG = "false";
            KOMODO_DISABLE_USER_REGISTRATION = "true";
            KOMODO_ENABLE_NEW_USERS = "false";
            KOMODO_MONITORING_INTERVAL = "15-sec";
            KOMODO_RESOURCE_POLL_INTERVAL = "1-hr";
            KOMODO_JWT_TTL = "1-day";
            KOMODO_LOGGING_PRETTY = "false";
            KOMODO_PERIPHERY_PUBLIC_KEY = "file:/config/keys/periphery.pub";
          };
          environmentFiles = [ config.onepassword.templates.komodo-core.path ];
          extraOptions = [ "--network=komodo" "--init" ];
        };
      };

      # The backstop for `activate`. Core writes a new key pair when it finds
      # none, so even with activate on, it refuses to start until Leia's
      # private key is in place.
      systemd.services.docker-komodo-core.unitConfig.ConditionPathExists = coreKey;

      # virtualisation.oci-containers doesn't manage networks itself.
      systemd.services.komodo-network = {
        description = "Create the komodo docker network";
        wantedBy = [ "multi-user.target" ];
        before = [
          "docker-komodo-mongo.service"
          "docker-komodo-core.service"
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

      # Leia's periphery dials in to Core here, and Traefik on Leia proxies
      # the UI to it.
      networking.firewall.allowedTCPPorts = [ 9120 ];
    })
  ];
}
