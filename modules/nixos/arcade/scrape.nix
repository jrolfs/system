{ config, lib, pkgs, ... }:

# arcade-scrape: box art, screenshots and descriptions for the station's
# games, from ScreenScraper through Skyscraper, written as Pegasus metadata
# next to the ROMs.
#
# ScreenScraper works without an account but slowly, one thread and a short
# daily quota, so the account's credentials come from 1Password at run time:
# op://Secrets/ScreenScraper/{username,password}. They go into a config file
# readable only by whoever runs the scrape, in their runtime directory, and
# are gone when it exits. Not `-u user:password`, because a command line is
# visible to every user on the machine.
#
# Skyscraper writes its own header atop each metadata.pegasus.txt. The scrape
# ends by running arcade-collections, which puts back the one from
# pegasus.nix, so the launch line always comes from Nix.

let
  cfg = config.arcade;
  systems = import ./systems.nix;

  # No videos. The menu doesn't play them, and they would be most of a
  # scrape's download time against ScreenScraper's one-thread limit, and
  # gigabytes on disk. Off is Skyscraper's default; it's written out so that
  # turning it back on is a deliberate choice for a theme that can show them.
  settings = pkgs.writeText "skyscraper.ini" ''
    [main]
    inputFolder="${cfg.root}/roms"
    gameListFolder="${cfg.root}/roms"
    videos="false"
    unattend="true"
    verbosity="1"
  '';

  scrape = pkgs.writeShellApplication {
    name = "arcade-scrape";
    runtimeInputs = [
      pkgs.skyscraper
      config.programs._1password.package
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
    ];
    text = ''
      known=(${lib.concatStringsSep " " (lib.attrNames systems)})

      if [[ ''${1:-} == -h || ''${1:-} == --help ]]; then
        echo "usage: arcade-scrape [system...]"
        echo "systems: ''${known[*]}"
        exit 0
      fi

      platforms=("$@")
      if (( ''${#platforms[@]} == 0 )); then
        platforms=("''${known[@]}")
      fi

      for platform in "''${platforms[@]}"; do
        if ! printf '%s\n' "''${known[@]}" | grep -qx "$platform"; then
          echo "arcade-scrape: unknown system $platform (known: ''${known[*]})" >&2
          exit 64
        fi
      done

      if [[ -z ''${OP_SERVICE_ACCOUNT_TOKEN:-} ]]; then
        token="$HOME/.config/op/service-account-token"
        if [[ ! -r $token ]]; then
          echo "arcade-scrape: no 1Password service account token at $token" >&2
          exit 77
        fi
        OP_SERVICE_ACCOUNT_TOKEN=$(< "$token")
        export OP_SERVICE_ACCOUNT_TOKEN
      fi

      username=$(op read op://Secrets/ScreenScraper/username)
      password=$(op read op://Secrets/ScreenScraper/password)

      umask 077
      private=$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/arcade-scrape.XXXXXX")
      trap 'rm -rf "$private"' EXIT

      {
        cat ${settings}
        printf '\n[screenscraper]\nuserCreds="%s:%s"\n' "$username" "$password"
      } > "$private/config.ini"

      # The metadata files and media are shared with the arcade user.
      umask 002

      for platform in "''${platforms[@]}"; do
        if [[ -z $(find "${cfg.root}/roms/$platform" -maxdepth 1 -type f ! -name metadata.pegasus.txt -print -quit) ]]; then
          echo "arcade-scrape: no games in ${cfg.root}/roms/$platform, skipping"
          continue
        fi

        # Skyscraper works in two passes: gather from the source into its
        # cache, then generate the front end's files from the cache.
        Skyscraper -c "$private/config.ini" -p "$platform" -s screenscraper
        Skyscraper -c "$private/config.ini" -p "$platform" -f pegasus
      done

      arcade-collections
    '';
  };
in
lib.mkIf cfg.enable {
  environment.systemPackages = [ scrape ];
}
