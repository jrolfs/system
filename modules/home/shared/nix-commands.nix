{ config, lib, pkgs, hostname, inputs, ... }:

# The commands for working on this configuration from a shell: nix-switch,
# nix-rebuild, nix-update and nix-search. One definition for every machine,
# nix-switch as a command on PATH and the rest as aliases in
# ~/.config/zsh/init/nix.zsh (which .zshrc sources), with each platform
# supplying only what differs: how it rebuilds, and on macOS the Homebrew flags. The two used to be separate hand-written copies, and drifted:
# Linux had a bare alias with none of the flags.
#
# nix-switch takes:
#
#   --pull              fast-forward the tree being switched first, from any
#                       directory
#   --update            refresh flake.lock first, all inputs or, with
#   --update=<input>    --update=nixpkgs, just that one (repeat for several)
#   --worktree          switch the worktree of this repo the shell is in
#   --worktree=<branch> switch the worktree with that branch checked out
#   --main              switch the main checkout, even from inside a worktree
#
# plus whatever the platform adds, and passes anything else through to the
# rebuild. --update has to be asked for: the rebuild only ever reads the lock,
# which is what makes a bare nix-switch reproducible, so moving inputs
# underneath it silently would cost more than the keystrokes save. The lock
# change is left uncommitted on purpose, to be reviewed with the switch that
# used it.
#
# Run from inside a worktree under ~/.config/.system with none of the last
# three, nix-switch switches that worktree and says so, because testing a
# branch is the usual reason to be there. It is limited to that directory
# because a worktree can end up anywhere: `wt restore` recreates one at
# whatever path it had on the machine that handed it off, and that is how a
# stale migration-era worktree once sat in ~/.homesick/repos. Switching to one
# of those by accident would be hard to notice and slow to undo, so outside
# ~/.config/.system it takes --worktree. Either way the switch lasts until the
# next one: a later nix-switch from the main checkout puts main back.
#
# A worktree is still built as a git flake, so untracked files are left out of
# it until they are `git add`ed, and a new module that isn't staged evaluates
# as if it did not exist.

let
  inherit (lib) mkOption types;

  cfg = config.nixCommands;

  # Baked in rather than read from $NIX_CONFIG_DIR and $(hostname -s) when the
  # shell starts. That variable is a home.sessionVariables entry, which lands in
  # hm-session-vars.sh, which nothing here sources — nix-darwin's /etc/zshenv
  # reads only its own set-environment, and home-manager's zsh integration is
  # inert while .zshrc is a lifted dotfile. The aliases were expanding to
  # `--flake #ala`.
  #
  # The hostname is the one this configuration was evaluated for, and it is what
  # selected this configuration in the first place, so asking the running system
  # was only ever a slower route to the same answer — and a wrong one if the
  # machine is mid-rename.
  directory = "${config.home.homeDirectory}/.config/system";
  flake = "${directory}#${hostname}";

  # Where worktrunk puts this repo's worktrees, from the `worktree-path` entry
  # for it in dotfiles/home/.config/worktrunk/config.toml. Only used to decide
  # whether a bare nix-switch should pick up the worktree it's run from; an
  # explicit --worktree finds the tree through git wherever it lives.
  worktrees = "${config.home.homeDirectory}/.config/.system";

  # Every flake input, for completing --update=<input> and nix-update's
  # arguments. Taken from the flake that built this configuration, so it's
  # exactly the set flake.lock knows about.
  inputNames = lib.concatStringsSep " "
    (builtins.attrNames (removeAttrs inputs [ "self" ]));

  flagSpecs = lib.concatMapStrings
    (flag: " \\\n          '${flag.pattern}[${flag.description}]'")
    cfg.flags;

  flagCases = lib.concatMapStrings
    (flag: "      ${flag.pattern}) ${flag.action} ;;\n")
    cfg.flags;

  # A command rather than a shell function, so it can be run from places that
  # never source nix.zsh: worktrunk aliases (`wt land` in .config/wt.toml
  # switches back to main after a merge), hooks, other scripts. It never
  # changes the calling shell's state, so nothing was lost by moving it out.
  #
  # The body is a function so `return` keeps working in the platform's
  # beforeSwitch, which was written for one.
  nixSwitch = pkgs.writeScriptBin "nix-switch" # zsh
    ''
      #!${pkgs.zsh}/bin/zsh -f

      # Prints the tree to build. `mode` is auto (no flag), main, here (a bare
      # --worktree) or branch (--worktree=<branch>). A worktree is recognised
      # by its git common directory being the main checkout's, so a directory
      # under ${worktrees} that belongs to some other repo falls back to main
      # rather than being switched to.
      tree_for() {
        local mode=$1 branch=$2 main='${directory}' tree common

        case $mode in
          main)
            print -r -- $main
            return
            ;;
          branch)
            tree=$(git -C $main worktree list --porcelain \
              | awk -v ref="refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0=="branch " ref {print p}')
            if [[ -z $tree ]]; then
              print -u2 "nix-switch: no worktree has $branch checked out"
              return 1
            fi
            print -r -- $tree
            return
            ;;
        esac

        if [[ $mode == auto && $PWD/ != '${worktrees}'/* ]]; then
          print -r -- $main
          return
        fi

        tree=$(git -C $PWD rev-parse --show-toplevel 2>/dev/null)
        common=$(git -C $PWD rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        if [[ $common == $main/.git ]]; then
          print -r -- $tree
        elif [[ $mode == auto ]]; then
          print -r -- $main
        else
          print -u2 "nix-switch: $PWD is not in a worktree of $main"
          return 1
        fi
      }

      main() {
      ${cfg.delegate}
        local update=no pull=no mode=auto branch= tree ${cfg.locals}
        local -a rest inputs

        for argument in "$@"; do
          case "$argument" in
            --pull) pull=yes ;;
            --update) update=yes ;;
            --update=*) update=yes; inputs+=("''${argument#--update=}") ;;
            --main) mode=main ;;
            --worktree) mode=here ;;
            --worktree=*) mode=branch; branch=''${argument#--worktree=} ;;
      ${flagCases}      *) rest+=("$argument") ;;
          esac
        done

        tree=$(tree_for $mode $branch) || return

        if [[ $tree != '${directory}' ]]; then
          print -u2 "nix-switch: switching worktree $(git -C $tree branch --show-current) ($tree#${hostname})"
          [[ $mode == auto ]] && print -u2 "            --main switches ${directory} instead"
        fi

        # Before --update: the update rewrites flake.lock, which a pull
        # afterwards would collide with.
        if [[ $pull == yes ]]; then
          git -C $tree pull --ff-only || return
        fi

        if [[ $update == yes ]]; then
          nix flake update --flake $tree "''${inputs[@]}" || return
        fi

      ${cfg.beforeSwitch}
        ${cfg.switch} --flake "$tree#${hostname}" --show-trace "''${rest[@]}"
      }

      main "$@"
    '';
in
{
  options.nixCommands = {
    switch = mkOption {
      type = types.str;
      description = "Command line that switches to the flake, before `--flake`.";
    };

    build = mkOption {
      type = types.str;
      description = "Command line that builds the flake, before `--flake`.";
    };

    locals = mkOption {
      type = types.str;
      default = "";
      description = "Extra `name=value` locals for nix-switch, for platform flags to set.";
    };

    flags = mkOption {
      default = [ ];
      description = "Platform flags for nix-switch, each a case pattern and the zsh it runs.";
      type = types.listOf (types.submodule {
        options = {
          pattern = mkOption { type = types.str; };
          action = mkOption { type = types.str; };
          description = mkOption {
            type = types.str;
            description = "Shown beside the flag when completing.";
          };
        };
      });
    };

    beforeSwitch = mkOption {
      type = types.lines;
      default = "";
      description = "zsh run after --pull and --update, just before the switch.";
    };

    delegate = mkOption {
      type = types.lines;
      default = "";
      description = ''
        zsh run first, before any argument is read, that may hand the whole
        nix-switch off to something else and `return` its status. The
        arguments are still in "$@".
      '';
    };
  };

  # On fpath through ~/.config/zsh/completions, so compinit finds it by its
  # #compdef line. It can't be registered from nix.zsh: that is sourced before
  # compinit runs, when compdef doesn't exist yet.
  config.xdg.configFile."zsh/completions/_nix-switch".text = # zsh
    ''
      #compdef nix-switch nix-update

      _nix_switch_worktrees() {
        local -a branches
        branches=(''${(f)"$(git -C '${directory}' worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p')"})
        _describe 'worktree branch' branches
      }

      case $service in
        nix-update)
          _arguments '*:flake input:(${inputNames})'
          ;;
        nix-switch)
          _arguments \
            '--pull[fast-forward the tree being switched first]' \
            '*--update=-[refresh flake.lock first, all inputs or the one named]::flake input:(${inputNames})' \
            '(--main)--worktree=-[switch a worktree: this one, or the branch named]::worktree branch:_nix_switch_worktrees' \
            '(--worktree)--main[switch ~/.config/system even from a worktree]'${flagSpecs}
          ;;
      esac
    '';

  # Quoted wherever the flake reference appears: unquoted, zsh's extendedglob
  # reads the `#` in `system#<host>` as a pattern operator, finds no file
  # matching it, and refuses to run the command.
  config.xdg.configFile."zsh/init/nix.zsh".text = # zsh
    ''
      alias nix-search="nix search nixpkgs"
      alias nix-rebuild="${cfg.build} --flake '${flake}' --show-trace"

      # --flake takes the directory, not the #hostname reference the rebuild
      # wants. Naming inputs updates only those: `nix-update nixpkgs`.
      alias nix-update="nix flake update --flake '${directory}'"
    '';

  config.home.packages = [ nixSwitch ];
}
