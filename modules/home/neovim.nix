{ pkgs, lib, config, inputs, ... }:

# Everything that makes ~/.config/nvim: where the config comes from, the
# sessions the kitty layout loads, and the two things that have to happen on a
# machine that has never seen either.
#
# The config is its own repo (jrolfs/neovim) and it is edited from a clone, not
# from the pinned input. Sourced from the input, every file under ~/.config/nvim
# was a read-only store symlink: `:w` on the config failed outright, and the
# loop for a one-line lua tweak was commit → push → `nix flake update
# neovim-config` → switch. The input still pins the *provenance* — it's what
# supplies the list of things to link, and what a machine without the clone
# would need — but the links point at the working copy.

let
  clone = "${config.home.homeDirectory}/Developer/Sources/jrolfs/neovim";
  cloneConfig = "${clone}/home/.config/nvim";
  cloneUrl = "https://github.com/jrolfs/neovim.git";

  live = "${config.home.homeDirectory}/.config/system/dotfiles/home";

  entryPoints = [ "init.vim" "init-kitty.vim" ];

  # Only the top level is enumerated, so everything below it is live: a new
  # module in lua/, a new file in mappings/, a rewritten nvim-pack-lock.json.
  # The list comes from the input because an absolute path can't be read under
  # pure eval — which makes a *new top-level entry* the one change that still
  # needs `nix flake update neovim-config` and a switch.
  #
  # Not one symlink for the whole directory, for the reason liveConfig exists
  # in default.nix: ~/.config/nvim has to stay a real directory. sessions/ is
  # managed below, and the private castle plants dot--private.vim in there too.
  configTree = lib.concatMapAttrs
    (name: _:
      lib.optionalAttrs (name != "sessions") {
        "nvim/${name}".source = config.lib.file.mkOutOfStoreSymlink "${cloneConfig}/${name}";
      })
    (builtins.readDir "${inputs.neovim-config}/home/.config/nvim");

  # Public repo, cloned over plain HTTPS with the user's git config out of the
  # way — the same reasoning as the warm-up below: activation is the wrong place
  # to depend on an SSH key being present and unlocked, and a credential prompt
  # would hang the switch with nothing on screen to explain why. The remote
  # stays HTTPS, which a normal shell rewrites to SSH via the config's
  # insteadOf, so pushing from the clone works as usual.
  cloneScript = pkgs.writeShellScript "neovim-config-clone" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.git pkgs.coreutils ]}:$PATH
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_TERMINAL_PROMPT=0

    [ -e ${lib.escapeShellArg clone}/.git ] && exit 0

    mkdir -p "$(dirname ${lib.escapeShellArg clone})"
    timeout 300 git clone --quiet ${cloneUrl} ${lib.escapeShellArg clone}
  '';

  # Neovim installs its own plugins: `vim.pack.add` clones whatever is missing
  # when the config loads, so a fresh machine sits at zero plugins until the
  # first interactive launch. This boots each entry point once, headlessly, so
  # the machine arrives warm.
  #
  # Both entry points are needed and neither substitutes for the other: init.vim
  # and init-kitty.vim (kitty's scrollback pager) declare different plugin sets
  # in lua/packages/, and each is only ever loaded by its own host application.
  # They do write into one shared pack directory, which is what lets the guard
  # below be a single emptiness check.
  warmUp = pkgs.writeShellScript "neovim-pack-warmup" ''
    set -uo pipefail

    export PATH=${lib.makeBinPath [ pkgs.git pkgs.openssh pkgs.coreutils ]}:$PATH

    # Plugin repositories are public, so clone them over plain HTTPS: the
    # user's git config rewrites github.com to SSH, and activation is the wrong
    # place to depend on a key being present and unlocked. GIT_TERMINAL_PROMPT
    # matters more than it looks — without it a credential prompt would hang
    # the switch indefinitely, with nothing on screen to explain why.
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_TERMINAL_PROMPT=0

    status=0

    # -c runs after the config is sourced, so this overrides init.vim's
    # `let g:session_autosave = 'yes'` — otherwise a warm-up would overwrite
    # the saved default session on its way out.
    boot() {
      # Same reasoning as the prompt: a wedged clone should fail the step, not
      # stall the switch behind it.
      timeout 600 ${pkgs.neovim}/bin/nvim --headless \
        -u "${config.xdg.configHome}/nvim/$1" \
        -c 'let g:session_autosave = "no"' -c 'qa'
    }

    for entry in ${lib.escapeShellArgs entryPoints}; do
      echo "neovim: installing plugins for $entry"

      # Two passes. The first is expected to be noisy: plugins are cloned
      # while the config is already running, so anything the config `require`s
      # from a plugin that did not exist yet fails on the way past. The second
      # pass is the one whose exit status means something.
      boot "$entry" || true
      boot "$entry" || status=1
    done

    exit $status
  '';
in
{
  xdg.configFile = configTree // {
    # The two sessions the kitty dotfiles layout opens (the third,
    # dot--private.vim, comes from the private castle). In this repo rather
    # than the neovim one because they describe *this* repo's layout — and
    # excluded from the tree above so sessions/ stays a real directory owned by
    # home-manager instead of one more thing landing in the clone's git status.
    #
    # Out of store because :mksession! rewrites the file it was loaded from, so
    # this is what makes saving a rearranged layout work at all. Nothing linked
    # these before: a fresh machine got the tabs with no session to load, and
    # the recursive nvim entry hid them from the unlinked-file audit.
    "nvim/sessions/system.vim".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.config/nvim/sessions/system.vim";
    "nvim/sessions/neovim.vim".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.config/nvim/sessions/neovim.vim";
  };

  # Every link above points into the clone, so on a machine that doesn't have
  # one yet the whole config dangles — including the entry points the warm-up
  # boots, hence before it. Nothing else needs the clone this early: dangling
  # symlinks are created happily and resolve the moment it lands.
  home.activation.neovimConfigClone = lib.hm.dag.entryBetween [ "neovimPack" ] [ "writeBoundary" ] # bash
    ''
      run ${cloneScript} \
        || warnEcho "neovim: could not clone ${cloneUrl} to ${clone} — ~/.config/nvim is dangling until it exists"
    '';

  # Runs on every activation rather than only when the pack directory is empty.
  # `vim.pack.add` is a no-op for plugins that are already cloned, so the cost
  # of the warm case is two nvim boots — and gating on emptiness would mean a
  # plugin added to the config after the first switch never got installed by
  # one, which is the case this module exists to cover.
  home.activation.neovimPack = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run ${warmUp} \
        || warnEcho "neovim: plugin install did not complete — :checkhealth vim.pack in an interactive session"
    '';
}
