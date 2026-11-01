{ pkgs, lib, hostname, userName, ... }:

# Beelink SEi 12 Mini PC — i5-12450H, 16 GB RAM, 500 GB SSD.
# Home-infra host, taking over Leia's services in the phases laid out in
# documentation/IRULAN-MIGRATION.md. Services that suit a NixOS module run
# natively from here; the rest are Komodo stacks in the rolfs.lan repo, which
# this host's periphery deploys.
#
# hardware-configuration.nix is NOT imported here yet — it gets generated
# by `nixos-generate-config --root /mnt` during the install on real
# hardware and lands at /etc/nixos/hardware-configuration.nix. After the
# install, copy it into hosts/irulan/ and add the import line below.

{
  imports = [
    ./disko.nix
    # ./hardware-configuration.nix              # TODO: add after install

    ../../modules/nixos/desktop
    ../../modules/nixos/arcade

    ../../modules/nixos/services/komodo
    ../../modules/nixos/services/plex.nix
    ../../modules/nixos/services/home-assistant
    ../../modules/nixos/services/agent-vm.nix

    # Needs state that still lives on Leia and is placed by hand before first
    # start (the CA data and its intermediate password). Imported without it,
    # it fails every switch: nixos-rebuild exits non-zero whenever a unit
    # fails to start. Bring it back in alongside its migration.
    # ../../modules/nixos/services/step-ca.nix
  ];

  # Core moves here from Leia, ahead of the services it deploys
  # (documentation/KOMODO-CORE-CUTOVER.md). `activate` was held off until
  # Leia's database and Core's key pair were carried over, which happened on
  # 2026-11-01; turning it off again stops Core here, the start of rolling back.
  komodo.periphery.enable = true;

  # The irulan-monitoring Komodo stack (rolfs.lan's irulan/monitoring), phase 2
  # of documentation/IRULAN-MIGRATION.md. Kuma's database lives here rather
  # than in the periphery's clone, so redeploys never touch it.
  systemd.tmpfiles.rules = [
    "d /srv/monitoring/uptime-kuma 0750 root root - -"
    # The irulan-dns stack's Pi-hole (phase 5): gravity and the query log,
    # outside the periphery's clone for the same reason as Kuma's.
    "d /srv/dns/pihole 0755 root root - -"
  ];

  # Kuma's Matter monitor reaches the Matter server on this host from the
  # stack's bridge, which the compose file names br-monitoring. Only that
  # network gets the port: the Matter server's API is unauthenticated, so it
  # isn't opened to the LAN.
  networking.firewall.interfaces.br-monitoring.allowedTCPPorts = [ 5580 ];

  # The primary Pi-hole is a macvlan container on this host at 10.10.10.1, and
  # the kernel never delivers traffic between a macvlan endpoint and its parent
  # interface. Without this the host, and Home Assistant on its network, would
  # time out on the first DNS server DHCP hands out before falling back. A
  # second macvlan on enp3s0, with one address and a route to .1 only, gives
  # the host a path to its own Pi-hole; nothing else is routed through it.
  # 10.10.10.4 is recorded in rolfs.lan's kath/network.md.
  networking.macvlans.lan-shim = {
    interface = "enp3s0";
    mode = "bridge";
  };
  networking.interfaces.lan-shim = {
    # Explicit, so dhcpcd leaves it alone and a future change to enp3s0's
    # DHCP setting can't spill onto it.
    useDHCP = false;
    ipv4.addresses = [ { address = "10.10.10.4"; prefixLength = 32; } ];
    ipv4.routes = [ { address = "10.10.10.1"; prefixLength = 32; } ];
  };
  # IPv4 only. Left alone it takes router advertisements like enp3s0 does, and
  # a second on-link route for the LAN's IPv6 prefix could send Matter's local
  # traffic out of the shim. Set as the interface appears, since a boot-time
  # sysctl runs before it exists.
  #
  # And answering ARP only for its own address. By default Linux answers on
  # any interface for any address the host holds, so the shim replied to
  # dhcpcd's duplicate-address probes for enp3s0's lease with its own MAC;
  # dhcpcd took that as a conflict, declined each lease in turn and left
  # enp3s0 without 10.10.10.9.
  systemd.services.lan-shim-netdev.postStart = ''
    echo 1 > /proc/sys/net/ipv6/conf/lan-shim/disable_ipv6
    echo 1 > /proc/sys/net/ipv4/conf/lan-shim/arp_ignore
    echo 2 > /proc/sys/net/ipv4/conf/lan-shim/arp_announce
  '';

  # Docker's veth and bridge interfaces aren't dhcpcd's. Unlisted, it probed
  # them for link-local addresses and, while enp3s0 was between leases,
  # routed the default route through one.
  networking.dhcpcd.denyInterfaces = [ "veth*" "br-*" "docker*" ];
  komodo.core = {
    enable = true;
    activate = true;
    # Leia's Core was v2.1.2 when its database moved here, and a database
    # only migrates forward; 2.3.3 is also Irulan's periphery, from nixpkgs.
    imageTag = "2.3.3";
  };

  # Stack secrets, synced from 1Password into Komodo secret variables. A stack
  # reads one through its Environment as NAME=[[NAME]].
  komodo.secrets = {
    DHCP_PROBE_PUSH_URL = "op://Secrets/dhcp-probe/push url";
    # nebula-sync logs in to both Pi-holes with it (irulan-dns).
    PIHOLE_WEBPASSWORD = "op://Secrets/Pi-hole/password";
  };

  # Home Assistant and the Matter server, moved here from Leia in phase 4 of
  # documentation/IRULAN-MIGRATION.md. serveLegacyAddress gives Irulan
  # 10.10.10.2, Home Assistant's address on Leia, so devices, the companion
  # apps and Traefik's route find it where they always have. Leia's containers
  # are stopped with their restart policy off, and must stay that way while
  # this is on, or the two would fight over the address.
  homeAssistant = {
    enable = true;
    serveLegacyAddress = true;
  };

  # A microVM running opencode's server, for agents to work in without the
  # rest of this machine in reach.
  agentVm = {
    enable = true;
    externalInterface = "enp3s0";
    telegramBot = {
      enable = true;
      allowedUserId = 6908664565;
    };
  };

  # Attached to a TV with a keyboard and trackpad, so it boots to a desktop
  # even though most of what it runs is headless, with the emulator station
  # beside it (documentation/ARCADE.md).
  desktop.enable = true;
  keyboard.enable = true;
  # The Magic Keyboard and Trackpad pair over it, and have to work at the
  # console as well as in the desktop.
  hardware.bluetooth.enable = true;
  arcade.enable = true;

  # The TV (and the receiver behind it) on and off with the machine, through
  # Home Assistant's control of the Frame, since this HDMI port has no CEC.
  av = {
    enable = true;
    entity = "media_player.living_room_living_room_smart";
  };

  # Boots to the text console until the desktop's first-boot crash is fixed.
  # The `desktop` and `station` commands still start either one by hand.
  sessions.boot = "console";

  networking.hostName = hostname;
  networking.useDHCP = lib.mkDefault true;  # static IP TBD; DHCP for now.
  networking.firewall.enable = true;

  users.users.${userName} = {
    isNormalUser = true;
    home = "/home/${userName}";
    shell = pkgs.zsh;
    # A NixOS account with no password is *locked*, not passwordless — and
    # with PasswordAuthentication off and authorized_keys not written until
    # the GPG key is imported, a fresh install without this is a machine
    # nobody can log into except the root console.
    #
    # Safe to commit to a public repo: yescrypt is memory-hard, and sshd
    # refuses passwords, so this only ever unlocks a keyboard someone is
    # standing in front of.
    #
    # `initial` is load-bearing. mutableUsers defaults to true, so this
    # applies only when the account is created — it seeds the install, and
    # `passwd` afterwards sticks. A reinstall falls back to this.
    # Verify against the vault before an install, by re-hashing with this
    # value's own salt: `op read 'op://Secrets/Irulan/password' |
    # mkpasswd -m yescrypt -S "$(cut -d'$' -f1-4 <<< "$hash")" -s`. The two
    # drifted once already, because regenerating the 1Password item does not
    # touch this file, and the failure only shows up as a password that
    # doesn't work on a machine nobody can log into.
    initialHashedPassword = "$y$j9T$4w877UixkTowZS062uf13/$Pfc3xrJns0xQ8Sv.wdqlVbnADcXHREqDVXtN9i.14XC";
    # video + render: Plex hardware transcoding via Quick Sync.
    # docker: invoke docker without sudo (Komodo periphery + ad-hoc).
    extraGroups = [ "wheel" "video" "render" "docker" ];
  };

  # Intel UHD Graphics (12th-gen) hardware video decode + encode for Plex.
  # intel-media-driver covers Broadwell+ (the i5-12450H's iGPU); the
  # legacy intel-vaapi-driver is unnecessary on this chip.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
    ];
  };

  # i915 loads its GuC and HuC firmware from linux-firmware, and on 12th-gen
  # the low-power encoder Quick Sync relies on doesn't work without HuC. The
  # generated hardware-configuration.nix doesn't turn this on by itself.
  hardware.enableRedistributableFirmware = true;

  # The Docker daemon Komodo deploys stacks to, through the periphery.
  virtualisation.docker.enable = true;

  # SSH for `nixos-rebuild switch --target-host jamie@irulan` from
  # another machine. Keys flow in via home-manager (private castle).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # Leia's media share, read-only: the download stack on Leia is the only
  # writer, and two Plex servers scanning one tree must not both be able to
  # rewrite it. The library DB (services.plex.dataDir) is on the local SSD.
  # x-systemd.automount + noauto: don't block boot if the NAS is down; mount
  # on first access instead.
  #
  # The version is left to negotiation. QTS offers 4.1 at most, and a pinned
  # nfsvers fails outright against a server without it instead of falling back.
  #
  # The export is /Media under QTS's NFSv4 pseudo-root. Leia only grants it to
  # irulan.rolfs.lan, so Irulan's LAN traffic has to come from its own address
  # (the reason Home Assistant's 10.10.10.2 is a /32).
  #
  # Mounted again at the two paths Leia's Plex library recorded its media
  # under, so the moved database resolves every file without its paths being
  # rewritten. QTS reached the same share both ways.
  fileSystems = lib.genAttrs [
    "/mnt/nas/media"
    "/share/Media"
    "/share/MD0_DATA/Media"
  ] (_: {
    device = "leia.rolfs.lan:/Media";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "ro"
      "soft"
    ];
  });

  # `/` and `/boot` come from disko.nix — it owns the partition table and
  # generates the matching fileSystems entries, so the placeholders that used
  # to live here (just enough for the host to evaluate without hardware) are
  # gone.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Compressed swap in RAM instead of a swap partition: 16 GB stretches
  # further under Plex transcodes plus Komodo's containers, with no SSD writes.
  # Nothing here hibernates, which is the one thing zram can't back.
  zramSwap.enable = true;
}
