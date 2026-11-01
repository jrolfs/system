{ pkgs, lib, hostname, userName, ... }:

# Beelink SEi 12 Mini PC — i5-12450H, 16 GB RAM, 500 GB SSD.
# Home-infra host: native Home Assistant + Plex + step-ca; bootstrap-tier
# Komodo containers; everything else lives in the compose repo and is
# deployed via Komodo periphery.
#
# hardware-configuration.nix is NOT imported here yet — it gets generated
# by `nixos-generate-config --root /mnt` during the install on real
# hardware and lands at /etc/nixos/hardware-configuration.nix. After the
# install, copy it into hosts/irulan/ and add the import line below.

{
  imports = [
    ./disko.nix
    # ./hardware-configuration.nix              # TODO: add after install

    # Attached to a TV with a keyboard, so it gets the GUI applications even
    # though it spends most of its life headless.
    ../../modules/nixos/desktop.nix

    ../../modules/nixos/services/home-assistant.nix
    ../../modules/nixos/services/plex.nix
    ../../modules/nixos/services/step-ca.nix
    ../../modules/nixos/services/komodo.nix
  ];

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
    initialHashedPassword = "$y$j9T$bfhk1LFVc.iTrIl0ZAREM1$vrA6U7F2fLQgZlBhaoNWiNr330JmBHauHjoKjOJBtU6";
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

  # Docker daemon for the bootstrap-tier Komodo containers (see
  # modules/nixos/services/komodo.nix). Komodo manages its own
  # containers via the docker socket.
  virtualisation.docker.enable = true;

  # SSH for `nixos-rebuild switch --target-host jamie@irulan` from
  # another machine. Keys flow in via home-manager (private castle).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # NFS mount of the QNAP media share. Plex / media services read from
  # here; library DB (services.plex.dataDir) is on the local SSD.
  # x-systemd.automount + noauto: don't block boot if NAS is down;
  # mount on first access; remount cleanly when network comes back.
  # TODO: confirm export path on QNAP (currently /share/Media exposed
  # via NFS on the NAS — adjust if QNAP exports a different path).
  fileSystems."/mnt/nas/media" = {
    device = "qnap.lan:/share/Media";
    fsType = "nfs";
    options = [
      "x-systemd.automount"
      "noauto"
      "_netdev"
      "nfsvers=4.2"
      "soft"
      "intr"
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
