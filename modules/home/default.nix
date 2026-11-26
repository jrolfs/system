{ pkgs, lib, hostname, userName, config, inputs, ... }:

let
  dotfiles = ../../dotfiles/home;
  repoRoot = ../..;

  # The working tree as it exists on the machine, as opposed to the store copy
  # of it that `dotfiles` refers to.
  live = "${config.home.homeDirectory}/.config/system/dotfiles/home";

  # Per-file out-of-store symlinks mirroring the structure of a directory under
  # dotfiles/home/.config. Two properties a single directory symlink can't
  # have at once: edits land in the next shell rather than the next switch, and
  # the directory stays a real one, so the private castle's files (zsh/keys.zsh,
  # zsh/init/keys.zsh) can sit alongside the managed ones.
  #
  # Adding a *new* file still needs a switch, since the tree is walked at
  # evaluation time — only the contents of existing files are live.
  liveConfig = name:
    let
      walk = relative:
        lib.concatMapAttrs
          (entry: type:
            let path = "${relative}/${entry}"; in
            if type == "directory" then
              walk path
            else {
              "${name}${path}".source =
                config.lib.file.mkOutOfStoreSymlink "${live}/.config/${name}${path}";
            })
          (builtins.readDir "${dotfiles}/.config/${name}${relative}");
    in
    walk "";

  # The hand-written gh extensions under dotfiles/home/.local/share/gh. Walked
  # rather than listed so adding one to the tree doesn't also need an entry
  # here, and linked file-by-file rather than as the directory above them:
  # `gh extension install` writes its own subdirectories into extensions/ (the
  # gh-stack binary is one), so that has to stay a real directory. gh finds
  # each extension by directory name and runs the like-named executable inside,
  # which is why both halves of the path repeat the name.
  ghExtensions = lib.concatMapAttrs
    (name: type:
      if type == "directory" then {
        ".local/share/gh/extensions/${name}/${name}".source =
          "${dotfiles}/.local/share/gh/extensions/${name}/${name}";
      } else { })
    (builtins.readDir "${dotfiles}/.local/share/gh/extensions");
in
{
  imports = [ ./neovim.nix ./ssh.nix ]
    ++ lib.optional (builtins.pathExists ./hosts/${hostname}.nix) ./hosts/${hostname}.nix;

  home.username = userName;
  home.stateVersion = "24.05";

  home.sessionVariables = {
    NIX_CONFIG_DIR = "${config.home.homeDirectory}/.config/system";
    HOMESHICK_KINGDOM = "${config.home.homeDirectory}/.homesick/repos";
  };

  programs.home-manager.enable = true;

  # nix-direnv replaces direnv's built-in `use flake` with a version that
  # caches the dev shell and keeps a GC root, so entering a project is instant
  # after the first time instead of re-evaluating the flake on every cd.
  #
  # The zsh hook stays in .zshrc under zinit's `nocd` (home-manager's would go
  # into programs.zsh.initContent, which is inert while .zshrc is a lifted
  # dotfile) — enabling both would just eval the hook twice.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = false;
  };

  # Top-level shell dotfiles. The .zshrc still has its
  # `source ~/.zshrc.<platform>` lookup; modules/home/darwin.nix provides
  # ~/.zshrc.darwin so that path resolves on macOS, nothing on linux.
  home.file = {
    ".zshenv".source = "${dotfiles}/.zshenv";
    ".zshrc".source = "${dotfiles}/.zshrc";
    ".zprofile".source = "${dotfiles}/.zprofile";
    ".zlogin".source = "${dotfiles}/.zlogin";
    ".zlogout".source = "${dotfiles}/.zlogout";
    ".agignore".source = "${dotfiles}/.agignore";
    ".editorconfig".source = "${dotfiles}/.editorconfig";

    # default-key, keyserver and no-emit-version say nothing about the
    # platform, and irulan needs them to sign commits as the same identity.
    # gpg-agent.conf is the part that differs, so each platform module declares
    # its own.
    ".gnupg/gpg.conf".source = "${dotfiles}/.gnupg/gpg.conf";

    # zinit comes from the flake input, not from the old
    # $HOMESHICK_KINGDOM/dot/zinit submodule path.
    #
    # The zinit.git/ subdirectory is not cosmetic: zinit resolves
    # ZINIT[HOME_DIR] to $XDG_DATA_HOME/zinit whenever that exists and writes
    # plugins/, snippets/, completions/ and polaris/ into it. Linking the
    # source there directly makes the directory zinit wants to own read-only,
    # so every plugin install fails. Upstream's own install puts the checkout
    # in a zinit.git/ subdirectory for exactly this reason, which leaves
    # ~/.local/share/zinit a real directory (and matches where newt's existing
    # plugin cache already lives).
    ".local/share/zinit/zinit.git".source = inputs.zinit;

    # `ls` is aliased to this wrapper (zsh/init/aliases.zsh), which is why it
    # can't just be a script nobody linked: without it every ls in every shell
    # is a "no such file or directory". It came over from the dot castle, where
    # homeshick had been linking it — nothing in the flake picked it up. Still
    # named exa-wrapper.sh there; renamed here along with the binary it calls.
    ".local/share/eza-wrapper.sh".source = "${dotfiles}/.local/share/eza-wrapper.sh";

    # ~/.claude is Claude Code's own state directory — projects/, todos/,
    # history.jsonl, a dozen caches — so the tracked entries inside it are
    # linked individually and the directory itself stays real. Without these
    # the global conventions in CLAUDE.md simply aren't in effect on a
    # provisioned machine.
    #
    # Out of store because these are written back to: `#` appends to CLAUDE.md,
    # settings.json is rewritten whenever a permission is granted, and a saved
    # slash command lands in commands/. On newt they were symlinks into the dot
    # castle's working tree, which is the same shape: edits and additions are a
    # git diff, not a rebuild.
    #
    # bin/ is the exception, installed as a package (home.packages below)
    # instead.
    ".claude/CLAUDE.md".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.claude/CLAUDE.md";
    ".claude/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.claude/settings.json";
    ".claude/keybindings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.claude/keybindings.json";
    ".claude/commands".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.claude/commands";
  } // ghExtensions;

  # The helpers from dotfiles/home/.claude/bin as commands, rather than a
  # ~/.claude/bin nothing puts on PATH: claude-mv-project is typed at a prompt,
  # claude-zed-threads is run by the resume-zed function and the like-named
  # slash command, and both of those had to spell out the absolute path to find
  # it. Editing one now takes a switch to take effect, which is the trade for
  # the interpreter no longer being whatever `env python3` resolves to (see the
  # package in overlays/default.nix).
  home.packages = [ pkgs.claude-helpers ];

  # Migration guard for machines that switched while the entry above was
  # `.local/share/zinit` rather than `.local/share/zinit/zinit.git`, which is
  # every machine provisioned between a669185 and cafbe20.
  #
  # home-manager's orphan cleanup cannot make that transition. It walks the old
  # generation's links and deletes the ones whose path is absent from the new
  # generation — but `.local/share/zinit` is *present* there, as a directory, so
  # the stale link is left in place. linkGeneration then resolves the new
  # zinit.git through it into /nix/store/…-zinit, which is mode 555 and owned by
  # root, and `ln` fails with EACCES. Activation runs under `set -eu`, so that
  # takes the rest of it with it — the neovim warm-up, the font sync and every
  # launchd agent.
  #
  # Only a symlink is removed, never a directory: once the transition has
  # happened this is a real directory that zinit owns, holding the plugin,
  # snippet and completion caches it clones at runtime. Safe to delete this
  # block once no machine is still on a pre-cafbe20 generation.
  home.activation.zinitHomeDirectory =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] # bash
      ''
        if [ -L "${config.xdg.dataHome}/zinit" ]; then
          run rm $VERBOSE_ARG "${config.xdg.dataHome}/zinit"
        fi
      '';

  # kitty.conf sets `listen_on unix:~/.local/share/kitty/socket`, and kitty
  # bind()s that socket while starting up without creating the directory it
  # lives in. Boss.__init__ wraps the call in a bare `except Exception`, so a
  # missing parent comes out as ENOENT and gets reported as
  # "Invalid listen_on=…-<pid>, ignoring" in the config-error dialog on every
  # launch — with the socket never created, which takes `kitty @ --to` with it
  # (the set-font-size helper in zsh/init/functions.zsh and the stay/ action
  # scripts both locate it by globbing this directory).
  home.activation.kittySocketDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run mkdir -p "${config.xdg.dataHome}/kitty"
    '';

  # gpg refuses to use a home directory that is readable by anyone else, and
  # the one home-manager creates on its way to linking gpg.conf gets the
  # default 755.
  home.activation.gnupgPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
    ''
      run chmod 700 "${config.home.homeDirectory}/.gnupg"
    '';

  # ~/.config/spicetify used to be one symlink for the whole directory and is
  # now a real directory of per-file links (see xdg.configFile below). Nothing
  # in home-manager performs that conversion: it links the new generation
  # before it cleans the old one, and the cleanup then keeps the old symlink
  # because the new generation has an entry by the same name. So the stale
  # link is still standing when the links below it are created, `mkdir -p` and
  # `ln -s` follow it into the working copy, and config-xpui.ini lands there
  # pointing at the store path that points back at it. spicetify opens its own
  # config, gets ELOOP, and silently falls back to a default config with no
  # theme.
  #
  # Guarded on -L so this only ever removes the old whole-directory link, not
  # the real directory that replaces it.
  home.activation.spicetifyDirectoryLink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] # bash
    ''
      if [ -L "${config.xdg.configHome}/spicetify" ]; then
        run rm $VERBOSE_ARG "${config.xdg.configHome}/spicetify"
      fi
    '';

  # XDG config directories. Each lifts an entire subtree from
  # dotfiles/home/.config/ except where the app writes back to its dir
  # — those use mkOutOfStoreSymlink so the link target stays mutable.
  xdg.configFile = lib.mkMerge [
    # Edited far too often to want a rebuild in the loop: prompt, aliases,
    # functions and the zinit snippets under init/ are all sourced fresh by
    # every new shell, so a live link means editing one is just editing a file.
    (liveConfig "zsh")

    {
    # git is recursive rather than a single directory symlink because the
    # private homeshick castle plants git/authors.yml inside it and bootstrap
    # links the castle before the first switch. A directory symlink would put
    # that file in the way on every fresh machine, and once the store link won
    # that fight there'd be nowhere writable for homeshick to put it back.
    # (zsh has the same overlap, handled by liveConfig above.)
    "git" = {
      source = "${dotfiles}/.config/git";
      recursive = true;
    };

    "atuin".source = "${dotfiles}/.config/atuin";
    "bat".source = "${dotfiles}/.config/bat";
    # Only the toml, not the whole dir — programs.direnv.nix-direnv writes
    # direnv/lib/hm-nix-direnv.sh into this same tree, and a single symlink
    # for the directory would collide with it.
    "direnv/direnv.toml".source = "${dotfiles}/.config/direnv/direnv.toml";
    # Not a bare link to the dotfiles tree, because themes/current.conf is a
    # *relative* symlink to gruvbox-material/colors/gruvbox-material-dark-soft.conf
    # and the gruvbox-material directory it points into was a submodule of the
    # old `dot` castle. Nothing in the flake ever put it back, so the link has
    # been dangling on every machine provisioned from this repo: kitty silently
    # skips the failed `include themes/current.conf` and applies only
    # themes/customizations.conf, which is why the colours were wrong rather
    # than absent.
    #
    # A relative symlink resolves against the directory holding it, so the
    # theme has to end up in the *same* store path as current.conf — hence the
    # copy-and-merge rather than an extra xdg.configFile entry beside this one
    # (which would land in ~/.config/kitty/themes while current.conf kept
    # resolving inside /nix/store). recursive = true has the same problem for
    # the same reason.
    #
    # Keeping current.conf as the switch means changing variants stays a
    # one-symlink edit in the tracked tree, as it was before.
    #
    # kittens/{grab,smart-scroll} are the same story: castle submodules that
    # bindings.conf loads by relative path (`kitten kittens/grab/grab.py`), so
    # they have to resolve inside this store path too. The tracked tree still
    # carries them as the old dangling submodule symlinks, hence the rm.
    #
    # kitty-scrollback.nvim is the exception, and needs nothing here. Its kitten
    # ships alongside the neovim plugin, which vim.pack clones into
    # $XDG_DATA_HOME at runtime (packages/kitty.lua) rather than arriving as an
    # input, so bindings.conf names it by ~-relative path instead.
    "kitty".source = pkgs.runCommandLocal "kitty-config" { } ''
      cp -R ${dotfiles}/.config/kitty $out
      chmod -R u+w $out
      ln -s ${inputs.kitty-gruvbox-material} $out/themes/gruvbox-material
      rm -f $out/kittens/grab $out/kittens/smart-scroll
      ln -s ${inputs.kitty-grab} $out/kittens/grab
      ln -s ${inputs.kitty-smart-scroll} $out/kittens/smart-scroll
    '';
    "mise".source = "${dotfiles}/.config/mise";
    "k9s".source = "${dotfiles}/.config/k9s";
    "tridactyl".source = "${dotfiles}/.config/tridactyl";
    "worktrunk".source = "${dotfiles}/.config/worktrunk";
    "tabtab".source = "${dotfiles}/.config/tabtab";
    "starship".source = "${dotfiles}/.config/starship";
    "starship.toml".source = "${dotfiles}/.config/starship.toml";

    # zed writes back into its config dir (settings.json, keymap.json
    # change from the UI) — mkOutOfStoreSymlink points at the real
    # working copy so writes land in the repo where they can be committed.
    "zed".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/system/dotfiles/home/.config/zed";

    # Same as zed, but for the one file rather than the directory: the
    # spicetify-watcher agent runs `spicetify backup apply` on every Spotify
    # update, which rewrites config-xpui.ini. spicetify truncates and rewrites
    # in place, so the write follows the link through to the working copy.
    #
    # The directory around it has to stay a real one, because Themes/ below is
    # a store path and because spicetify creates CustomApps/ and Extensions/
    # beside it at startup, and neither belongs in the tracked tree.
    "spicetify/config-xpui.ini".source =
      config.lib.file.mkOutOfStoreSymlink "${live}/.config/spicetify/config-xpui.ini";

    # current_theme in config-xpui.ini. spicetify looks a theme up in
    # $XDG_CONFIG_HOME/spicetify/Themes first and its own executable directory
    # second, so this is the only place a theme it didn't download itself can
    # go. Was a submodule of the old `dot` castle reached by a relative symlink
    # in the tracked tree, dangling since the migration: spicetify exits with
    # `Theme "gruvbox-material" not found` and the watcher logs a failure on
    # every Spotify update.
    #
    # Read-only, which only rules out `spicetify color <field> <value>`, the
    # one command that writes color.ini back into the theme. Changing the
    # scheme means forking the input.
    "spicetify/Themes/gruvbox-material".source = inputs.spicetify-gruvbox-material;

    # Same as zed, three times over: Glide regenerates glide.d.ts into this
    # directory, it's a pnpm project (node_modules), and its .envrc has direnv
    # writing .direnv/ there. All three need a writable path.
    "glide".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/system/dotfiles/home/.config/glide";

    # ~/.config/nvim is neovim.nix's — config tree, sessions and the clone it
    # all points at.
    }
  ];
}
