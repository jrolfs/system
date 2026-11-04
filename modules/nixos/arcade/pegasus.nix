{ config, lib, pkgs, ... }:

# Pegasus, the game menu, and what it reads.
#
# Each system's collection (its name, file extensions and RetroArch launch
# line) is written by Nix as the header of that system's metadata.pegasus.txt,
# in the ROM directory itself. That file is also where arcade-scrape's
# Skyscraper writes game metadata and media paths, underneath the header,
# and Skyscraper keeps whatever header it finds. One file per system, one
# collection per system, with no second definition for Pegasus to merge or
# show twice. arcade-collections rewrites the headers at boot and on every
# switch, so a changed core or extension list reaches files that already have
# scraped games in them.
#
# The theme is the station's own (theme/), drawn after the desktop shell's
# launcher from the same palette, fonts and style values in modules/theme.
# It replaced pegasus-theme-grid recolored by substitution, which could change
# colours but never shapes, blur or motion, and those were the point.

let
  cfg = config.arcade;
  systems = import ./systems.nix;
  fonts = import ../../theme/fonts.nix;

  home = config.users.users.arcade.home;
  configDirectory = "${home}/.config/pegasus-frontend";

  theme = pkgs.callPackage ./theme/package.nix { };

  # Pegasus writes these back when they're changed from its own menu. As
  # store links they can't be, so a change made on the TV lasts until Pegasus
  # restarts and the configuration stays what this file says.
  settings = pkgs.writeText "pegasus-settings.txt" ''
    general.theme: themes/station/
    general.fullscreen: true
    general.input-mouse-support: false
    general.verify-files: true
    general.scan-on-launch: true
    general.show-missing-games: false
    providers.es2.enabled: false
    providers.steam.enabled: false
    providers.gog.enabled: false
    providers.lutris.enabled: false
    providers.logiqx.enabled: false
    providers.skraper.enabled: false
  '';

  gameDirectories = pkgs.writeText "pegasus-game-dirs.txt"
    (lib.concatMapStrings (name: "${cfg.root}/roms/${name}\n") (lib.attrNames systems));

  headers = pkgs.linkFarm "arcade-collection-headers" (lib.mapAttrsToList
    (name: system: {
      inherit name;
      path = pkgs.writeText "${name}-header" ''
        collection: ${system.name}
        shortname: ${name}
        extensions: ${lib.concatStringsSep ", " system.extensions}
        launch: ${cfg.launch.${name}}
      '';
    })
    systems);

  collections = pkgs.writeShellApplication {
    name = "arcade-collections";
    runtimeInputs = [ pkgs.coreutils pkgs.gawk ];
    text = ''
      for header in ${headers}/*; do
        system=$(basename "$header")
        file="${cfg.root}/roms/$system/metadata.pegasus.txt"

        games=
        if [[ -f $file ]]; then
          games=$(awk '/^game:/ { found = 1 } found' "$file")
        fi

        staging=$(mktemp "$file.XXXXXX")
        {
          cat "$header"
          if [[ -n $games ]]; then
            printf '\n%s\n' "$games"
          fi
        } > "$staging"

        chmod 664 "$staging"
        mv -f "$staging" "$file"
      done
    '';
  };

in
lib.mkIf cfg.enable {
  environment.systemPackages = [ pkgs.pegasus-frontend collections ];

  fonts.packages = [ pkgs.${fonts.sans.package} ];

  systemd.tmpfiles.rules = [
    "d ${home}/.config 0755 arcade arcade - -"
    "d ${configDirectory} 0755 arcade arcade - -"
    "d ${configDirectory}/themes 0755 arcade arcade - -"
    "L+ ${configDirectory}/themes/station - - - - ${theme}"
    # The recolored grid theme's link, left pointing at a store path nothing
    # keeps alive any more.
    "r ${configDirectory}/themes/gruvbox-material - - - - -"
    "L+ ${configDirectory}/settings.txt - - - - ${settings}"
    "L+ ${configDirectory}/game_dirs.txt - - - - ${gameDirectories}"
  ];

  systemd.services.arcade-collections = {
    description = "Write the emulator station's collection headers";
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "arcade-station.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      # Kept active so a switch that changes the headers runs it again.
      RemainAfterExit = true;
      User = "arcade";
      Group = "arcade";
      UMask = "0002";
      ExecStart = lib.getExe collections;
    };
  };
}
