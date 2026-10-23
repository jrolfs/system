{ config, pkgs, userName, ... }:
let
  # Hardcoded because builtins.getEnv returns "" under pure flake eval.
  #
  # The asset tree is read out of the deployed configuration rather than
  # ~/.local/share/icons, which is where homeshick used to put it — and only
  # ever as a symlink chain that ended in this same repo. Nothing else refers to
  # that path (the `icn` alias in modules/home/darwin/default.nix already points here),
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

  # The xattr, FinderInfo and Icon\r plumbing that icon-setter shares with
  # folder-icons.nix. See pkgs/custom-icon.rs for why it is shared.
  customIcon = pkgs.rustLibrary {
    name = "custom-icon";
    src = ./pkgs/custom-icon.rs;
  };

  # A small tool that sets custom icons on macOS app bundles via direct POSIX
  # file I/O, writing the Icon\r resource fork and FinderInfo xattr by hand and
  # completely bypassing NSWorkspace / osascript. This sidesteps the TCC and
  # com.apple.macl restrictions that block the NSWorkspace API when run from a
  # LaunchDaemon.
  #
  # Accepts both .icns and .png input; PNGs are wrapped in an icns container
  # on the fly (single ic10 entry, which macOS downscales as needed).
  iconSetter = pkgs.rustTool {
    name = "icon-setter";
    src = ./pkgs/icon-setter.rs;
    libraries = [ customIcon ];
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

        "''${run[@]}" "$app" "$icon" 2>&1
        case $? in
          0)
            echo "[$ts] ok: $name"
            echo "$name" >> "'"$results"'"
            ;;
          # A SIP-protected bundle can never take a custom icon, so it is not a
          # failure to chase: the apps Apple ships are symlinks into the
          # cryptex. No apostrophes in here, the whole block is single-quoted.
          3) echo "[$ts] skipped: $name (SIP-protected)" ;;
          *) echo "[$ts] FAILED: $name" ;;
        esac
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

  logPath = "${configDirectory}/icons/launchd.log";
in
{
  environment.systemPackages = [ script ];

  # Writing inside a MACL'd app bundle needs Full Disk Access, which cannot be
  # granted to this script directly: TCC would evaluate /bin/bash, and the store
  # path moves every rebuild anyway. fda.nix owns the one binary that holds the
  # grant, and this reaches the access through it.
  fda.operations.icons = script;

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
      ProgramArguments = [ config.fda.runPath "icons" ];
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
