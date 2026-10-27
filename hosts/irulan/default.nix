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

    ../../modules/nixos/services/komodo.nix
    ../../modules/nixos/services/plex.nix
    ../../modules/nixos/services/agent-vm.nix

    # Needs state that still lives on Leia and is placed by hand before first
    # start (the CA data and its intermediate password). Imported without it,
    # it fails every switch: nixos-rebuild exits non-zero whenever a unit
    # fails to start. Bring it back in alongside its migration.
    # ../../modules/nixos/services/step-ca.nix
  ];

  # Core stays on Leia. Enabling it here would also need /etc/komodo/*.env
  # placed by hand first, for the reason step-ca is commented out above.
  komodo.periphery.enable = true;

  # A microVM running opencode's server, for agents to work in without the
  # rest of this machine in reach.
  agentVm = {
    enable = true;
    externalInterface = "enp3s0";
  };

  # Attached to a TV with a keyboard and trackpad, so it boots to a desktop
  # even though most of what it runs is headless, with the emulator station
  # beside it (documentation/ARCADE.md).
  desktop.enable = true;
  keyboard.enable = true;
  arcade.enable = true;

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
  # TODO: confirm the export path. QTS exports NFSv4 under a pseudo-root
  # named after the share (/Media), and v3 at /share/Media. On Leia,
  # `cat /etc/exports` shows both, and Control Panel → Shared Folders →
  # Media → Edit Shared Folder Permission → NFS host access is where Irulan
  # has to be allowed (read-only is enough).
  fileSystems."/mnt/nas/media" = {
    device = "leia.rolfs.lan:/Media";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "ro"
      "soft"
    ];
  };

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
