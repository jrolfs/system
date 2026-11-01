{ config, lib, pkgs, inputs, userName, ... }:

# A sandbox for coding agents: a Cloud Hypervisor microVM running opencode's
# server, so an agent can run whatever it needs to with nothing of the host's
# in reach but its own workspace. It's a VM rather than a container because an
# agent runs code it pulls in, and a container would share this kernel with
# it. Cloud Hypervisor rather than Firecracker because it can share
# directories over virtiofs: the guest mounts the host's /nix/store read-only
# instead of carrying its own image, so the VM is a few megabytes of
# configuration and rebuilds with the host.
#
# What the agent can reach:
#
# - Its workspace and opencode's state, shared from /var/lib/agent-vm. The
#   guest's user has uid 1000, so on the host both belong to the user who
#   runs this machine, and its work can be picked up directly.
# - The internet, through NAT. Private ranges are rejected, which covers the
#   LAN, Leia, the Docker networks and the tailnet.
# - The host on the key proxy's ports and nothing else. API keys never enter
#   the guest. Its opencode talks to http://<host>:<port>, and the proxy adds
#   the real key on the way out to the provider, so a compromised agent can
#   spend a key but never read it.
#
# Networking is routed rather than bridged: the tap interface is a
# point-to-point link with a /32 at each end, so the guest shares an Ethernet
# segment with nothing. The host side is configured by systemd-networkd, which
# runs beside the scripted networking that manages everything else here, and
# dhcpcd is kept off the tap.
#
# opencode's server listens on the guest's address, reachable from the host
# only, and requires the password in /var/lib/agent-vm/opencode/password,
# generated on first start. Publishing it beyond the host is a separate step.

let
  cfg = config.agentVm;

  name = "agent";
  tap = "vm-agent";
  mac = "02:00:00:00:a6:01";
  hostAddress = "10.100.0.1";
  guestAddress = "10.100.0.2";
  opencodePort = 4096;
  state = "/var/lib/agent-vm";
  home = "/var/lib/opencode/home";

  # Each provider the guest's opencode can use, by its opencode ID. `header`
  # and `prefix` are how the provider expects its key.
  providers = {
    anthropic = { port = 8401; upstream = "api.anthropic.com"; header = "x-api-key"; prefix = ""; };
    openai = { port = 8402; upstream = "api.openai.com"; header = "Authorization"; prefix = "Bearer "; };
  };

  keyFile = provider: "/home/${userName}/.config/api-keys/${provider}";

  private = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "100.64.0.0/10" "169.254.0.0/16" ];

  # nginx run as the host user, whose files secrets.nix writes the keys into.
  # The config is assembled at start so the keys only ever live in a 0700
  # runtime directory, never the store.
  proxyConfig = pkgs.writeShellScript "agent-vm-key-proxy-config" ''
    set -eu
    dir=$RUNTIME_DIRECTORY
    conf=$dir/nginx.conf
    # IPv4 only: this host has no IPv6 route out, and nginx otherwise tries a
    # provider's IPv6 address first and waits out the connect timeout. A
    # resolver is what makes ipv6=off possible, and it only applies to a
    # proxy_pass through a variable.
    printf 'daemon off;\npid %s/nginx.pid;\nerror_log stderr;\nevents {}\nhttp {\n  access_log off;\n  resolver 9.9.9.9 149.112.112.112 ipv6=off;\n' "$dir" > "$conf"
    for temp in client_body proxy fastcgi uwsgi scgi; do
      printf '  %s_temp_path %s/%s;\n' "$temp" "$dir" "$temp" >> "$conf"
    done
    ${lib.concatStrings (lib.mapAttrsToList (provider: p: ''
      key=$(tr -d '\n' < ${lib.escapeShellArg (keyFile provider)})
      printf '  server {\n    listen %s;\n    set $upstream %s;\n    location / {\n      proxy_pass https://$upstream;\n      proxy_ssl_server_name on;\n      proxy_set_header Host %s;\n      proxy_set_header %s "%s%s";\n      proxy_http_version 1.1;\n      proxy_buffering off;\n      proxy_read_timeout 900s;\n    }\n  }\n' \
        ${toString p.port} ${p.upstream} ${p.upstream} ${lib.escapeShellArg p.header} ${lib.escapeShellArg p.prefix} "$key" >> "$conf"
    '') providers)}
    printf '}\n' >> "$conf"
  '';
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  options.agentVm = {
    enable = lib.mkEnableOption "the opencode agent microVM";

    externalInterface = lib.mkOption {
      type = lib.types.str;
      description = "The host interface the guest's traffic leaves through.";
    };

    telegramBot = {
      enable = lib.mkEnableOption "a Telegram client for the VM's opencode server";

      allowedUserId = lib.mkOption {
        type = lib.types.int;
        description = "The one Telegram user the bot answers.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    microvm.autostart = [ name ];

    microvm.vms.${name}.config = { lib, pkgs, ... }: {
      system.stateVersion = config.system.stateVersion;
      networking.hostName = name;

      microvm = {
        hypervisor = "cloud-hypervisor";
        vcpu = 4;
        mem = 4096;

        interfaces = [ { type = "tap"; id = tap; inherit mac; } ];

        shares = [
          { proto = "virtiofs"; tag = "ro-store"; source = "/nix/store"; mountPoint = "/nix/.ro-store"; }
          { proto = "virtiofs"; tag = "workspace"; source = "${state}/workspace"; mountPoint = "/workspace"; }
          { proto = "virtiofs"; tag = "opencode"; source = "${state}/opencode"; mountPoint = "/var/lib/opencode"; }
        ];
      };

      networking.useNetworkd = true;
      systemd.network.networks."10-uplink" = {
        matchConfig.MACAddress = mac;
        address = [ "${guestAddress}/32" ];
        routes = [
          { Destination = "${hostAddress}/32"; GatewayOnLink = true; }
          { Destination = "0.0.0.0/0"; Gateway = hostAddress; GatewayOnLink = true; }
        ];
        networkConfig.DNS = [ "9.9.9.9" "149.112.112.112" ];
      };

      networking.firewall.allowedTCPPorts = [ opencodePort ];

      # uid 1000 so the shared directories belong to the host's own user.
      users.users.agent = {
        isNormalUser = true;
        uid = 1000;
        inherit home;
        createHome = false;
      };

      environment.systemPackages = with pkgs; [ opencode git curl ripgrep fd jq gnumake ];

      # Inside the VM the VM is the boundary, so opencode doesn't ask before
      # acting. Keys are placeholders: the host's proxy supplies the real ones.
      environment.etc."agent-vm/opencode.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        providers = lib.mapAttrs
          (_: p: {
            settings = {
              baseURL = "http://${hostAddress}:${toString p.port}/v1";
              apiKey = "supplied-by-host";
            };
          })
          providers;
      };

      systemd.tmpfiles.rules = [
        "d ${home} 0700 agent users -"
        "d ${home}/.config/opencode 0700 agent users -"
        "L+ ${home}/.config/opencode/opencode.json - - - - /etc/agent-vm/opencode.json"
      ];

      systemd.services.opencode = {
        description = "opencode server";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = with pkgs; [ git openssh coreutils bash ];
        script = ''
          OPENCODE_SERVER_PASSWORD=$(cat /var/lib/opencode/password)
          export OPENCODE_SERVER_PASSWORD
          exec ${pkgs.opencode}/bin/opencode serve --hostname ${guestAddress} --port ${toString opencodePort}
        '';
        serviceConfig = {
          User = "agent";
          WorkingDirectory = "/workspace";
          Environment = [ "HOME=${home}" ];
          Restart = "always";
          RestartSec = 5;
        };
      };
    };

    # The shared directories, and the server password, before the VM or its
    # virtiofsd instances start. A unit of its own rather than a preStart on
    # theirs, which are microvm.nix's templates.
    systemd.services.agent-vm-state = {
      description = "State directories for the agent microVM";
      requiredBy = [ "microvm-virtiofsd@${name}.service" "microvm@${name}.service" ];
      before = [ "microvm-virtiofsd@${name}.service" "microvm@${name}.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 -o 1000 -g 100 ${state} ${state}/workspace ${state}/opencode
        if [ ! -s ${state}/opencode/password ]; then
          ${pkgs.openssl}/bin/openssl rand -base64 32 | tr -d '\n' > ${state}/opencode/password
          chown 1000:100 ${state}/opencode/password
          chmod 0600 ${state}/opencode/password
        fi
      '';
    };

    systemd.network = {
      enable = true;

      # networkd manages the tap alone, and the tap is not required for being
      # online, so its wait-online service had nothing it could ever wait for
      # and failed every switch after its two-minute timeout.
      wait-online.enable = false;

      networks."30-${tap}" = {
        matchConfig.Name = tap;
        address = [ "${hostAddress}/32" ];
        routes = [ { Destination = "${guestAddress}/32"; } ];
        linkConfig.RequiredForOnline = "no";
      };
    };
    networking.dhcpcd.denyInterfaces = [ "vm-*" ];

    # Enabling networkd brings systemd-resolved with it, which takes
    # /etc/resolv.conf over. dhcpcd still owns the uplink and has no way to
    # hand resolved the router's DNS servers, so resolved fell back to public
    # ones, every rolfs.lan name stopped resolving (Leia's NFS media share among
    # them), and 1Password was unreachable for the secrets step in the gap while
    # it started. The guest names its own DNS servers, so nothing here needs it.
    services.resolved.enable = false;

    networking.nat = {
      enable = true;
      internalIPs = [ "${guestAddress}/32" ];
      externalInterface = cfg.externalInterface;
    };

    # Docker sets the FORWARD policy to DROP, so the guest's traffic needs its
    # own accept, after the rejects that keep it off every private range.
    networking.firewall.extraCommands = ''
      iptables -N agent-vm-forward 2>/dev/null || iptables -F agent-vm-forward
      iptables -A agent-vm-forward -d ${guestAddress} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      ${lib.concatMapStrings (net: ''
        iptables -A agent-vm-forward -s ${guestAddress} -d ${net} -j REJECT
      '') private}
      iptables -A agent-vm-forward -s ${guestAddress} -o ${cfg.externalInterface} -j ACCEPT
      iptables -D FORWARD -j agent-vm-forward 2>/dev/null || true
      iptables -I FORWARD 1 -j agent-vm-forward
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D FORWARD -j agent-vm-forward 2>/dev/null || true
    '';

    # From the guest, only the key proxy's ports on the host.
    networking.firewall.interfaces.${tap}.allowedTCPPorts = lib.mapAttrsToList (_: p: p.port) providers;

    systemd.services.agent-vm-key-proxy = {
      description = "API key proxy for the agent microVM";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = userName;
        RuntimeDirectory = "agent-vm-key-proxy";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = proxyConfig;
        ExecStart = "${pkgs.nginx}/bin/nginx -e stderr -c %t/agent-vm-key-proxy/nginx.conf -p %t/agent-vm-key-proxy";
        Restart = "on-failure";
        RestartSec = 10;
      };
    };

    # opencode from Telegram, for starting and following the VM's sessions
    # from a phone. It polls Telegram and calls the VM's server, and listens on
    # nothing. Only the configured user gets an answer.
    #
    # It runs here rather than in the guest because it needs the bot token,
    # and the guest never holds a credential. That puts it on a different
    # filesystem from the server, so /open, which browses folders on the bot's
    # machine, is pointed at an empty directory; projects come from /projects,
    # which asks the server. Its state, logs and the local-commands directory
    # it would run shell commands from live under its own XDG_CONFIG_HOME,
    # where nothing creates commands.
    systemd.services.agent-vm-telegram-bot = lib.mkIf cfg.telegramBot.enable {
      description = "Telegram client for the agent microVM's opencode";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "microvm@${name}.service" ];
      environment = {
        XDG_CONFIG_HOME = "/var/lib/agent-vm-telegram-bot";
        TELEGRAM_ALLOWED_USER_ID = toString cfg.telegramBot.allowedUserId;
        # No IPv6 route out of this host.
        TELEGRAM_FORCE_IPV4 = "true";
        OPENCODE_SERVER_VERSION = "v2";
        OPENCODE_API_URL = "http://${guestAddress}:${toString opencodePort}";
        OPENCODE_MODEL_PROVIDER = "anthropic";
        OPENCODE_MODEL_ID = "claude-opus-5-5";
        OPENCODE_AUTO_RESTART_ENABLED = "false";
        OPEN_BROWSER_ROOTS = "/var/empty";
      };
      script = ''
        TELEGRAM_BOT_TOKEN=$(cat /home/${userName}/.config/api-keys/telegram-opencode-bot)
        OPENCODE_SERVER_PASSWORD=$(cat ${state}/opencode/password)
        export TELEGRAM_BOT_TOKEN OPENCODE_SERVER_PASSWORD
        exec ${lib.getExe pkgs.opencode-telegram-bot} start --mode installed
      '';
      serviceConfig = {
        User = userName;
        StateDirectory = "agent-vm-telegram-bot";
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 10;
      };
    };
  };

}
