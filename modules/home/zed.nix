{ pkgs, lib, config, ... }:

# Zed itself is the Homebrew cask, and its config directory is linked wholesale
# in default.nix (Zed writes settings.json back from the UI, so the whole dir
# is an out-of-store symlink into the repo). Registry extensions ride the
# `auto_install_extensions` key in settings.json — Zed installs anything listed
# there that's missing, and never uninstalls, so the list converges a fresh
# machine and re-adds anything deleted by hand.
#
# What that key can't express is the dev extension: gruvbox-material-custom,
# which carries both the theme and the TypeScript/TSX/JSON(C) language
# overrides. Zed decides an extension is a dev extension purely by the entry
# under extensions/installed/ being a symlink (extension_host.rs:
# `is_dev = metadata.is_symlink`; index.json is just a cache it rebuilds), and
# "install dev extension" does nothing but compile the grammars and plant that
# symlink — so declaring the symlink *is* the install.

let
  clone = "${config.home.homeDirectory}/Developer/Sources/jrolfs/zed-gruvbox-material-custom";
  cloneUrl = "https://github.com/jrolfs/zed-gruvbox-material-custom.git";

  # Same shape as the neovim config clone (neovim.nix): public repo over plain
  # HTTPS with the user's git config out of the way, because activation is the
  # wrong place to depend on an SSH key being present and unlocked, and a
  # credential prompt would hang the switch with nothing on screen to explain
  # why. The remote stays HTTPS, which a normal shell rewrites to SSH via the
  # config's insteadOf, so pushing from the clone works as usual.
  cloneScript = pkgs.writeShellScript "zed-extension-clone" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils ]}:$PATH
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_TERMINAL_PROMPT=0

    [ -e ${lib.escapeShellArg clone}/.git ] && exit 0

    mkdir -p "$(dirname ${lib.escapeShellArg clone})"
    timeout 300 git clone --quiet ${cloneUrl} ${lib.escapeShellArg clone}
  '';
in
{
  home.file."Library/Application Support/Zed/extensions/installed/gruvbox-material-custom".source =
    config.lib.file.mkOutOfStoreSymlink clone;

  home.activation.zedExtensionClone = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${cloneScript} \
        || warnEcho "zed: could not clone ${cloneUrl} to ${clone} — the dev extension is dangling until it exists"

      # The compiled grammars are gitignored build artifacts, and only Zed can
      # produce them (there's no CLI for it — it downloads a wasi-sdk into
      # extensions/build/ and compiles). The theme half works straight off the
      # clone; the language overrides sit out until the grammars exist.
      if [ -e ${lib.escapeShellArg clone}/extension.toml ] \
        && [ ! -e ${lib.escapeShellArg clone}/grammars/tsx.wasm ]; then
        warnEcho "zed: grammars not compiled — run 'zed: rebuild dev extension' once to enable the language overrides"
      fi
    '';
}
