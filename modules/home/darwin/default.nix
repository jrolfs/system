{ lib, pkgs, config, userName, hostname, ... }:

# Darwin-only home-manager shared module. Loaded automatically for every
# darwinConfiguration via home-manager.sharedModules in flake.nix.

let
  dotfiles = ../../../dotfiles/home;

  configDirectory = "${config.home.homeDirectory}/.config/system";

  # gpg-agent execs pinentry-program fresh for every passphrase prompt, so
  # dispatching at that moment is what lets the `pin` toggle
  # (dotfiles/home/.config/zsh/init/gpg.zsh) be a one-line state file write with
  # no agent reload — and lets gpg-agent.conf stay a read-only store symlink
  # rather than something sed rewrites in place, which is what it used to be.
  #
  # Curses only works if there is a terminal to draw in, which rules it out for
  # anything a GUI starts — Zed's built-in git, say. That can't be detected
  # here: pinentry is a child of the daemon, so it has no tty of its own,
  # /dev/tty won't open, TERM is always "dumb", and the client's real tty
  # arrives over assuan as `OPTION ttyname` only *after* this has already
  # exec'd. The one thing gpg does put in the environment beforehand is
  # PINENTRY_USER_DATA, forwarded per-invocation as `OPTION putenv=`, so the
  # client has to say what it is rather than be sniffed.
  #
  # Interactive zsh sets `tty=<path>`; the path is checked instead of trusted
  # because a GUI app launched from a terminal inherits that terminal's
  # environment, and a long-lived agent keeps the environment of whichever
  # client happened to start it. macOS frees the pty node outright when a
  # terminal closes, so a marker that has outlived its terminal fails -c.
  #
  # Everything else — no marker, an unknown one, a terminal that has since gone
  # away — falls through to the GUI dialog, which is the direction that always
  # works: mac in a terminal is merely surprising, curses without one cannot
  # prompt at all.
  #
  # XDG_STATE_HOME is honoured if gpg-agent happens to have it, but the fallback
  # is an absolute path rather than $HOME/… — gpg-agent hands its child a
  # controlled environment, and a missing HOME here would silently mean "not
  # mac" forever.
  pinentry = pkgs.writeShellScript "pinentry-dispatch" ''
    mac=${pkgs.pinentry_mac}/bin/pinentry-mac
    curses=${pkgs.pinentry-curses}/bin/pinentry-curses
    state="''${XDG_STATE_HOME:-${config.home.homeDirectory}/.local/state}/pinentry"

    case "''${PINENTRY_USER_DATA-}" in
      # Per-invocation override, for a one-off `PINENTRY_USER_DATA=mac git push`.
      mac) exec "$mac" "$@" ;;
      curses) exec "$curses" "$@" ;;

      tty=*)
        terminal=''${PINENTRY_USER_DATA#tty=}

        if [ -c "$terminal" ] && [ -w "$terminal" ]; then
          if [ "$(cat "$state" 2>/dev/null)" = mac ]; then
            exec "$mac" "$@"
          fi

          exec "$curses" "$@"
        fi
        ;;
    esac

    exec "$mac" "$@"
  '';
in
{
  imports = [
    ./browsers.nix
    ./icloud.nix
    ./raycast.nix
    ./wallpaper.nix
  ];

  # Provide ~/.zshrc.darwin — sourced by ~/.zshrc when uname is Darwin.
  # NIX_PATH export is gone (the flake handles that via the system
  # nix.nixPath + registry entries in modules/darwin/default.nix).
  # nix-switch / nix-rebuild aliases now use --flake; icn points at the
  # consolidated repo's icons/ dir.
  # nix-switch and friends come from nix-commands.nix; this is the macOS part.
  #
  # darwin-rebuild has no way to elevate only the activation the way
  # nixos-rebuild --sudo does, and must run as root.
  #
  # --brew and --no-brew control `brew bundle`, which otherwise runs only when
  # the Brewfile changed (the gate in modules/darwin/homebrew.nix). --brew runs
  # it regardless, to pick up upstream cask releases or a version bump in a
  # jrolfs/tap .rb; --no-brew skips it for one switch.
  #
  # -H gives root its own HOME. This used to be `sudo -E`, which carried over
  # the per-machine NIX_MACOS_EXCLUDE_CASKS from before the flake. Nothing reads
  # that any more (exclusions are keyed by hostname in excluded-apps.nix, and a
  # pure flake evaluation can't see the environment anyway), and keeping this
  # user's HOME put root's evaluation cache in ~/.cache/nix owned by root, which
  # later evaluations as this user could not write to. The cleanup for that is
  # in modules/darwin/default.nix.
  nixCommands = {
    switch = "sudo -H darwin-rebuild switch";
    build = "sudo -H darwin-rebuild build";
    locals = "brew=auto flag=";
    flags = [
      { pattern = "--brew"; action = "brew=reset; flag=$argument"; description = "run brew bundle even if the Brewfile is unchanged"; }
      { pattern = "--no-brew"; action = "brew=skip; flag=$argument"; description = "skip brew bundle for this switch"; }
    ];
    # $brew doubles as the homebrew-gate subcommand. The gate is absent until
    # the switch that first installs it, so a flag passed on a fresh machine
    # warns instead of aborting the rebuild that would create it. The absolute
    # path is because sudo resets the environment, and this has to work from a
    # shell whose PATH has not been through brew shellenv yet.
    beforeSwitch = ''
      if [[ $brew != auto ]]; then
        if [[ -x /run/current-system/sw/bin/homebrew-gate ]]; then
          sudo /run/current-system/sw/bin/homebrew-gate "$brew" || return
        else
          echo "nix-switch: homebrew-gate not installed yet, ignoring $flag" >&2
        fi
      fi
    '';
  };

  home.file.".zshrc.darwin".text = # zsh
    ''
      #
      #
      # Aliases ----------------------------------------------------------------------

      alias mkbk="mackup backup -f && mackup uninstall -f"
      alias mkrs="mackup restore -f && mackup uninstall -f"

      alias icn="(cd ${configDirectory}/icons && sudo ./apply.sh)"

      alias spoon="$(brew --prefix)/bin/hs"


      #
      #
      # Functions --------------------------------------------------------------------

      function reset-host {
        host=$(hostname -s)

        echo "Setting HostName to ''${host}"
        sudo scutil --set HostName $host
        echo "Setting LocalHostName to ''${host}"
        sudo scutil --set LocalHostName $host
        echo "Setting ComputerName to ''${host}"
        sudo scutil --set ComputerName $host

        echo "Flushing DNS cache..."
        sudo killall -HUP mDNSResponder
      }

      #
      # GitHub CLI → Raycast

      source "$XDG_CONFIG_HOME/zsh/github-to-raycast.zsh"
    '';

  # system.defaults.screencapture.location points here, and screencapture
  # silently falls back to the desktop if the directory is missing — as it is on
  # a fresh machine. The dock also carries a tile for it, which would render as
  # a "?" placeholder.
  home.activation.screenshotsDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run mkdir -p "$HOME/Images/Screenshots"
    '';

  # karabiner writes back to its config dir (and we want the file
  # editable via the Karabiner-Elements UI too) — point at the live
  # working tree via an out-of-store symlink.
  xdg.configFile."karabiner" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.config/system/karabiner";
  };

  # hammerspoon: lift-and-shift the entire ~/.hammerspoon tree.
  # recursive = true keeps individual file symlinks so hammerspoon's
  # Spoons can drop state files alongside the Lua modules.
  home.file.".hammerspoon" = {
    source = "${dotfiles}/.hammerspoon";
    recursive = true;
  };

  # mackup config + database — kept on macOS so Homebrew-installed app
  # prefs that home-manager can't manage continue to sync.
  home.file.".mackup.cfg".source = "${dotfiles}/.mackup.cfg";
  home.file.".mackup" = {
    source = "${dotfiles}/.mackup";
    recursive = true;
  };

  # docker config (lift-and-shift; auth tokens get written here by
  # docker login — recursive so individual file overwrites work).
  home.file.".docker" = {
    source = "${dotfiles}/.docker";
    recursive = true;
  };

  # The two gnupg files that are macOS-specific: the pinentry choice only
  # arises here, and scdaemon is about a smartcard reader. gpg.conf is shared,
  # in modules/home/shared/default.nix. Declared per file rather than as a directory so
  # that ~/.gnupg stays writable for the keyrings and agent sockets that live
  # alongside them.
  #
  # Generated rather than lifted from the dotfiles tree because
  # pinentry-program has to name a store path; the other four lines are
  # verbatim from the dotfile this replaced.
  home.file.".gnupg/gpg-agent.conf".text = ''
    enable-ssh-support
    default-cache-ttl 600
    max-cache-ttl 7200
    pinentry-program ${pinentry}
    allow-preset-passphrase
  '';
  home.file.".gnupg/scdaemon.conf".source = "${dotfiles}/.gnupg/scdaemon.conf";

  # Raycast scripts (the personal "scripts" folder Raycast users
  # register). Preferences are untouched — those live in Library and
  # Raycast manages them itself.
  home.file.".local/share/raycast" = {
    source = "${dotfiles}/.local/share/raycast";
    recursive = true;
  };

  # VSCode and Cursor settings sync — both edit/write to the same
  # underlying repo at ~/.config/vscode-sync-settings/. mkOutOfStoreSymlink
  # points the Application Support dirs there so the sync-settings
  # extension can commit changes back to a real working tree (not the
  # nix store).
  home.file."Library/Application Support/Code/User" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.config/vscode-sync-settings/profiles/main";
  };
  home.file."Library/Application Support/Cursor/User" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/.config/vscode-sync-settings/profiles/main";
  };

  # The tridactyl native messaging host lives in modules/home/darwin/browsers.nix now,
  # as programs.firefox.nativeMessagingHosts, which gets it from
  # pkgs.tridactyl-native instead of from a vendored manifest and Python script.
}
