{ config, lib, pkgs, userName, ... }:
let
  # Hardcoded because builtins.getEnv returns "" under pure flake eval.
  #
  # The asset tree is read out of the deployed configuration rather than
  # ~/.local/share/icons, which is where homeshick used to put it — and only
  # ever as a symlink chain that ended in this same repo. Nothing else refers to
  # that path (the `icn` alias in modules/home/darwin.nix already points here),
  # and depending on it meant depending on a link that no longer gets created,
  # so fd had no search path and every run was a no-op.
  #
  # It also has to be a writable directory, not a store path: apply.log and
  # launchd.log are written alongside the assets, and icons/.gitignore covers
  # both. And it has to exist before home-manager activation runs, since the
  # LaunchAgent below watches it and glide-developer.nix invokes the script
  # during system activation — which the repo itself does, being the thing
  # darwin-rebuild was pointed at.
  configDirectory = "/Users/${userName}/.config/system";
  assetsDir = "${configDirectory}/icons/assets";

  # A small C tool that sets custom icons on macOS app bundles via direct
  # POSIX file I/O — writing the Icon\r resource fork and FinderInfo xattr
  # by hand, completely bypassing NSWorkspace / osascript.  This sidesteps
  # TCC and com.apple.macl restrictions that block the NSWorkspace API when
  # run from a LaunchDaemon.
  #
  # Accepts both .icns and .png input; PNGs are wrapped in an icns container
  # on the fly (single ic10 entry — macOS downscales as needed).
  iconSetter = pkgs.stdenv.mkDerivation {
    name = "icon-setter";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      $CC -O2 -Wall -o $out/bin/icon-setter ${./pkgs/icon-setter.c}
    '';
  };

  script = pkgs.writeShellScriptBin "icon-customizer" ''
    echo ""
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] run started"

    results=$(mktemp /tmp/icon-customizer.XXXXXX)

    ${pkgs.fd}/bin/fd \
      --type=f '\.(icns|png)$' ${assetsDir} \
      --exec /bin/zsh -c '
        ts=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
        icon="$1"

        # The app this icon targets is its path *relative to the assets
        # root*, with the extension dropped — so the asset tree mirrors
        # /Applications.  A top-level "Slack.png" targets
        # /Applications/Slack.app, while a nested
        # "Maxon Cinema 4D 2026/Cinema 4D.icns" targets
        # /Applications/Maxon Cinema 4D 2026/Cinema 4D.app (the folder is a
        # plain folder; the real bundle lives inside it).
        rel="''${icon#${assetsDir}/}"
        name="''${rel%.*}"
        app="/Applications/$name.app"

        if [[ ! -d "$app" ]]; then
          exit 0
        fi

        setter=${iconSetter}/bin/icon-setter
        if [[ "$(stat -f %Su "$app")" == "root" ]]; then
          run=(sudo "$setter")
        else
          run=("$setter")
        fi

        if "''${run[@]}" "$app" "$icon" 2>&1; then
          echo "[$ts] ok: $name"
          echo "$name" >> "'"$results"'"
        else
          echo "[$ts] FAILED: $name"
        fi
      ' zsh {}

    count=$(wc -l < "$results" 2>/dev/null | tr -d ' ')
    if [[ "$count" -gt 0 && "$ICON_CUSTOMIZER_NOTIFY" != "0" ]]; then
      apps=$(paste -sd, "$results" | sed 's/,/, /g')
      ${pkgs.terminal-notifier}/bin/terminal-notifier \
        -title "Icon Customizer" \
        -message "$count icon(s) updated: $apps"
    fi
    rm -f "$results"

    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] run finished"
  '';

  # A stable-path compiled wrapper so the agent can be granted Full Disk
  # Access once and the grant survives nix rebuilds (which change store
  # paths).  Must be a real Mach-O binary — TCC ignores FDA grants on
  # shell scripts (it evaluates /bin/bash instead of the script path).
  wrapper = pkgs.stdenv.mkDerivation {
    name = "icon-customizer-wrapper";
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/bin
      $CC -O2 -Wall -o $out/bin/icon-customizer ${./pkgs/icon-customizer-wrapper.c}
    '';
  };
  wrapperPath = "/usr/local/bin/icon-customizer";
  logPath = "${configDirectory}/icons/launchd.log";
in
{
  environment.systemPackages = [ script ];


  system.activationScripts.postActivation.text = lib.mkAfter # bash
    ''
      # Install a stable-path compiled wrapper for icon-customizer.
      # Must be a Mach-O binary (not a script) so TCC recognises the FDA
      # grant on the path.  The agent's ProgramArguments points here so the
      # user only has to grant Full Disk Access once (System Settings →
      # Privacy & Security → Full Disk Access → add
      # /usr/local/bin/icon-customizer).
      mkdir -p /usr/local/bin
      cp ${wrapper}/bin/icon-customizer ${wrapperPath}
      chmod +x ${wrapperPath}
    '';

  # Passwordless sudo for icon-setter so the LaunchAgent can customise icons on
  # root-owned app bundles (e.g. Kandji-managed apps).  Managed declaratively
  # via environment.etc — NOT a hand-rolled `echo` in postActivation — so
  # nix-darwin regenerates it on every switch in lockstep with the icon-setter
  # store path.  That path changes whenever icon-setter's build inputs change
  # (e.g. a toolchain bump on a nixpkgs update), and a stale rule silently
  # breaks NOPASSWD, unleashing one Touch ID prompt per root-owned app.  Same
  # pattern nix-darwin's built-in yabai module uses.  (nix-darwin renders this
  # as a symlink into the store, mode 0444 root-owned, which sudo accepts.)
  environment.etc."sudoers.d/icon-customizer".text =
    "jamie ALL=(root) NOPASSWD: ${iconSetter}/bin/icon-setter\n";

  # LaunchAgent (not Daemon) so the process runs in the user's login
  # session where FDA grants from System Settings actually apply.
  # All apps in /Applications are owned by the user, so root is not
  # needed — FDA alone is sufficient to write inside MACL'd bundles.
  launchd.user.agents.icon-customizer = {
    serviceConfig = {
      ProgramArguments = [ wrapperPath ];
      EnvironmentVariables.ICON_CUSTOMIZER_NOTIFY = "0";
      WatchPaths = [
        "/Applications"
        assetsDir
      ];
      RunAtLoad = true;
      StandardOutPath = logPath;
      StandardErrorPath = logPath;
      ThrottleInterval = 30;
    };
  };
}
