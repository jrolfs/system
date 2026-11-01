{ config, lib, pkgs, hostname, ... }:

let
  # State the activation gate below keeps between switches. Root-owned: the
  # skip token has to be something an unprivileged process can't plant, and
  # activation runs as root anyway.
  stateDirectory = "/var/lib/nix-darwin";
  stamp = "${stateDirectory}/homebrew.stamp";
  skipToken = "${stateDirectory}/homebrew.skip";

  # `brew bundle` is the slowest step in a switch by a wide margin, and on most
  # switches it has nothing to do: the Brewfile is derived entirely from the
  # lists below, so unless one of them moved, the run buys a `brew update` plus
  # a cask-by-cask check on the way to a no-op.
  #
  # Hashing the Brewfile's *content* rather than its store path is deliberate.
  # The store path also moves whenever pkgs.mas does, since brewBundleCmd puts
  # mas on PATH, and a nixpkgs bump is not a reason to re-run this. The
  # onActivation flags are folded in because they change what bundle is asked
  # to do without touching the Brewfile at all.
  #
  # What a content hash cannot see is what `nix-switch --brew` is for: a
  # version bump inside a jrolfs/tap cask .rb (see tap.nix), an upstream
  # release that `onActivation.upgrade` would otherwise pick up, or Homebrew
  # state edited by hand.
  bundleStateHash = builtins.hashString "sha256" (builtins.toJSON {
    inherit (config.homebrew) brewfile;
    inherit (config.homebrew.onActivation) autoUpdate cleanup upgrade extraFlags;
  });

  # The control surface for the gate. A script rather than an env var because
  # nix-darwin's activation script runs under `#!/usr/bin/env -i`, so nothing
  # set by the caller survives into it — the state has to arrive on disk.
  gate = pkgs.writeShellScriptBin "homebrew-gate" ''
    set -euo pipefail

    case "''${1:-}" in
      skip)
        mkdir -p ${stateDirectory}
        touch ${skipToken}
        ;;
      reset)
        rm -f ${stamp}
        ;;
      status)
        if [ "$(cat ${stamp} 2>/dev/null || true)" = "${bundleStateHash}" ]; then
          echo "current — brew bundle will be skipped on the next switch"
        else
          echo "stale — brew bundle will run on the next switch"
        fi
        ;;
      *)
        echo "usage: homebrew-gate {skip|reset|status}" >&2
        exit 1
        ;;
    esac
  '';

  excludeApps = (import ./excluded-apps.nix).${hostname} or [ ];

in

{
  homebrew.prefix = "/opt/homebrew";

  homebrew.onActivation.autoUpdate = true;
  homebrew.onActivation.cleanup = "zap";
  # nix-darwin defaults this false (so repeated switches are idempotent), which
  # passes `--no-upgrade` to `brew bundle` — meaning an already-installed cask is
  # never upgraded. That silently breaks the self-managed jrolfs/tap casks: bump
  # the pinned version + sha256 in the .rb, re-switch, and nothing happens.
  #
  # Trade-off accepted here: switches are no longer version-idempotent, since
  # every managed cask (Firefox, Chrome, …) may also upgrade on any switch. The
  # narrower alternative is to leave this false and upgrade the two self-managed
  # casks explicitly — see the note in tap.nix.
  homebrew.onActivation.upgrade = true;
  # No --force-cleanup in extraFlags: nix-darwin passes it itself now (for
  # Homebrew 4.7+), so setting it here produced `--force-cleanup
  # --force-cleanup`. It was needed against the older pinned nix-darwin.
  homebrew.enable = true;

  # Clear immutable flags from any applications managed by
  # self-service tools so Homebrew can manage all applications.
  system.activationScripts.extraActivation.text = lib.mkIf config.homebrew.enable (
    lib.mkAfter # bash
      ''
        if [ -d /Applications ]; then
          chflags -R noschg,nouchg /Applications 2>/dev/null || true
        fi
      ''
  );

  environment.systemPackages = [ gate ];

  # Replaces the homebrew module's own activation text rather than adding to
  # it, because the whole point is to decide whether its `brew bundle` runs.
  # The command itself is reused verbatim, so every onActivation option still
  # means what it means upstream.
  system.activationScripts.homebrew.text = lib.mkIf config.homebrew.enable (lib.mkForce # bash
    ''
      if [ -e ${skipToken} ]; then
        # Consumed here rather than by the wrapper that wrote it, so that a switch
        # interrupted before activation can't leave Homebrew gated off silently.
        rm -f ${skipToken}
        echo >&2 "Homebrew bundle... skipped (--no-brew)"
      elif [ ! -f "${config.homebrew.prefix}/bin/brew" ]; then
        echo >&2 -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m"
      elif [ "$(cat ${stamp} 2>/dev/null || true)" = "${bundleStateHash}" ]; then
        echo >&2 "Homebrew bundle... unchanged, skipped (nix-switch --brew to run anyway)"
      else
        echo >&2 "Homebrew bundle..."
        # Cleared before the run and written only after it returns. The script
        # runs under `set -e`, so a failed bundle aborts activation with no stamp
        # on disk and the next switch retries instead of recording it as done.
        rm -f ${stamp}
        ${config.homebrew.onActivation.brewBundleCmd { onlyCheck = false; }}
        mkdir -p ${stateDirectory}
        printf '%s\n' ${bundleStateHash} > ${stamp}
      fi
    '');

  homebrew.global.brewfile = true;

  # `brew bundle` runs during activation *before* home-manager links
  # ~/.config/git/config, so on a first switch git has no credential helper and
  # no URL rewrites. The private meterup tap and the `--HEAD` brews below (which
  # build from https://github.com/meterup/api.git) then die under Homebrew's
  # GIT_TERMINAL_PROMPT=0 with "could not read Username".
  #
  # /etc/gitconfig is the only git config in place that early, and it is read by
  # the git Homebrew actually shells out to (`brew --config` reports the Command
  # Line Tools git, not the nix one, whose system config lives inside its store
  # path). nix-darwin writes /etc at activation line ~2318; brew bundle runs at
  # ~2855.
  #
  # `store` reads ~/.git-credentials, which `bootstrap` materializes from
  # 1Password before the first switch. SSH is not usable here: keys minted by
  # bootstrap's OAuth App are barred from organization resources, so a fresh
  # machine's key can read personal private repos but not meterup's.
  #
  # The second rule looks like a no-op but isn't. Once home-manager has run, the
  # user config rewrites all of https://github.com/ to SSH; git resolves
  # insteadOf by *longest* matching prefix, so this pins meterup to HTTPS.
  #
  # The helper below only covers the *first* switch, though. The user config's
  # [credential "https://github.com"] section sets `helper =` (empty) before
  # adding gh's, and an empty value resets the accumulated list — verified with
  # `git credential fill` against a two-file config, where the system helper is
  # not consulted at all. So from the second switch on, the HTTPS path is served
  # by `gh auth git-credential` and needs `gh auth login` to have happened.
  environment.etc."gitconfig".text = # git_config
    ''
      [credential "https://github.com"]
      	helper = store

      [url "https://github.com/meterup/"]
      	insteadOf = https://github.com/meterup/
    '';

  homebrew.taps = [
    # jorgelbg/tap is gone: it carried only pinentry-touchid, which nothing
    # here uses — darwin's gpg-agent names pinentry-mac and linux.nix names
    # pinentry-curses. It had also become un-tappable, since its formula
    # declares no URL for the Linux platforms newer Homebrew validates at tap
    # time, so `brew tap` rejected the whole tap and failed the switch.
    { name = "jrolfs/tap"; trusted = true; }
    { name = "sozercan/repo"; trusted = true; }

    {
      # Private, so the clone needs a credential. It comes over HTTPS from
      # ~/.git-credentials via the helper configured above, rather than over
      # SSH with a clone_target: brew sanitizes SSH_AUTH_SOCK during
      # activation, and the on-disk key bootstrap mints can't reach org repos
      # anyway.
      name = "meterup/packages";
      trusted = true;
    }
  ];

  # mas is gone from here along with masApps: App Store installs are driven
  # directly by mas.nix now, and nothing else shells out to `mas`.
  homebrew.brews = [
    "openssl"

    { name = "meterup/packages/mcurl"; args = [ "HEAD" ]; }
    { name = "meterup/packages/mctl"; args = [ "HEAD" ]; }
    { name = "meterup/packages/hostsfile"; args = [ "HEAD" ]; }
  ];

  homebrew.casks = builtins.filter (app: !lib.elem app excludeApps) [

    "1password"
    "1password-cli"
    "acorn"
    "arq"
    "aws-vpn-client"
    "chatgpt"
    "claude"
    "cleanshot"
    "cursor"
    "daisydisk"
    "discord"
    "fantastical"
    "figma"
    "firefox"
    "firefox@developer-edition"
    "firefox@nightly"
    "glide-browser"
    "google-chrome"
    "google-chrome@beta"
    "google-chrome@canary"
    "grammarly-desktop"
    "hammerspoon"
    "jrolfs/tap/lingon-pro"
    "jrolfs/tap/unite-pro"
    "karabiner-elements"
    "kitty"
    "linear"
    "loom"
    "moom"
    "obsidian"
    "orbstack"
    "plex"
    "plexamp"
    "proxyman"
    "raycast"
    "resilio-sync"
    "safari-technology-preview"
    "signal"
    "slack"
    "spotify"
    "stay"
    "superhuman"
    "tailscale-app"
    "telegram"
    "whatsapp"
    "yaak"
    "zed"
    "zed@preview"
    "zoom"
    # back. Deleting that module restores the stock cask everywhere.
    # from source (patched for native picture in picture) or to add this cask
    # kaset is not listed here: kaset.nix decides per host whether to build it

    # Fonts
    "font-atkinson-hyperlegible"
    "font-fira-code-nerd-font"
    "font-geist"
    "font-hack-nerd-font"
    # Upstream split the single `font-ibm-plex` cask into one per family.
    # These are the Latin three; the rest (math, condensed, and the
    # arabic/devanagari/hebrew/jp/kr/sc/tc/thai scripts) exist under the same
    # prefix if ever wanted. Nothing in this config names IBM Plex, so this is
    # availability rather than a dependency.
    "font-ibm-plex-mono"
    "font-ibm-plex-sans"
    "font-ibm-plex-serif"
    "font-inter"
    "font-iosevka"
    "font-iosevka-slab"
    "font-jetbrains-mono"
    "font-jetbrains-mono-nerd-font"
    "font-public-sans"
  ];
}
