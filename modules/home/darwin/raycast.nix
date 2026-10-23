{
  pkgs,
  lib,
  config,
  ...
}:

# Raycast extensions that exist only on a branch of the jrolfs/extensions fork:
# ones written here and not yet accepted into the store, and other people's
# carrying a local fix. Each stays installed and usable until upstream
# publishes it, at which point dropping its entry from `tracked` below and
# removing the extension in Raycast hands the slot back to the store copy.
#
# Raycast has no declarative install. Its extension registry lives in
# SQLCipher-encrypted databases (settings_v2.db, node_extensions.db), so
# nothing outside the app can add a row. Everything *around* that registry is
# ordinary filesystem, though, and that is enough:
#
#   - Store extensions unpack into ~/.config/raycast/extensions/<uuid>/, but a
#     development extension lands in ~/.config/raycast/extensions/<name>/,
#     keyed by the `name` in its manifest. `ray build` computes precisely that
#     path when no --output is given (@raycast/api,
#     dist/utils/raycast-app-communication.js) and writes the bundled commands,
#     the processed package.json and assets/ into it. That directory is the
#     whole installed artifact.
#   - Registration is a deep link, not an API. The CLI shells out to
#     `/usr/bin/open -g -b com.raycast.macos
#     raycast://cli/<name>/<event>?cwd=<source>&info=`, where `start` and
#     `stop` bracket a `ray develop` session. Firing those by hand registers
#     the extension exactly as the watcher would, and `stop` does not
#     uninstall: bundle and registration both outlive it. A dev session lasting
#     two deep links is a permanent install.
#
# So the activation below *is* the install. Build into the directory Raycast
# reads, then tell Raycast to read it.
#
# The source is a worktrunk worktree of the fork rather than a checkout of its
# own, so the copy that is installed and the one `wt switch <branch>` lands in
# are the same tree. `wt dev` then hot-reloads the extension that is actually
# installed, and the branch it reloads from is the one that becomes the PR.
# ~/.config/worktrunk/config.toml drives that half and scopes each worktree's
# sparse cone from the branch name. What it cannot do is create the clone or
# set the per-clone partial-clone config its `sync` and `extension` aliases
# depend on, which is why both are done here.

let
  # Extension directory under extensions/, mapped to the branch carrying it.
  # The directory name is also the manifest `name`, hence the install path.
  tracked = {
    nerd-fonts = "add-nerd-fonts";
  };

  fork = "${config.home.homeDirectory}/Developer/Sources/jrolfs/extensions";
  forkUrl = "https://github.com/jrolfs/extensions.git";
  upstreamUrl = "https://github.com/raycast/extensions.git";

  installRoot = "${config.home.homeDirectory}/.config/raycast/extensions";
  stampRoot = "${config.xdg.stateHome}/raycast-extensions";

  # worktrunk's default worktree-path template, which this config leaves
  # unset: a sibling of the repo named `<repo>.<branch | sanitize>`, where
  # sanitize turns the path separators into dashes. Recomputed rather than
  # asked of `wt`, so a switch does not depend on worktrunk being installed.
  worktreeFor = branch: "${fork}." + builtins.replaceStrings [ "/" "\\" ] [ "-" "-" ] branch;

  script =
    pkgs.writeShellScript "raycast-extensions" # bash
      ''
        set -uo pipefail

        export PATH=${
          lib.makeBinPath [
            pkgs.git
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.nodejs_22
          ]
        }:$PATH

        # Same reasoning as the zed and neovim clones: activation is the wrong
        # place to depend on an SSH key being present and unlocked, and a
        # credential prompt would hang the switch with nothing on screen to say
        # why. The remote stays HTTPS, which a normal shell rewrites to SSH via the
        # git config's insteadOf, so pushing a PR from the worktree works as usual.
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_TERMINAL_PROMPT=0

        fork=${lib.escapeShellArg fork}
        fork_url=${lib.escapeShellArg forkUrl}
        upstream_url=${lib.escapeShellArg upstreamUrl}
        install_root=${lib.escapeShellArg installRoot}
        stamp_root=${lib.escapeShellArg stampRoot}

        # `open` launches Raycast when it is not running. During a switch that is
        # an unasked-for app launch, and a first registration would race the app's
        # startup anyway, so skip the deep links and leave the bundle in place.
        # The next switch with Raycast up finishes the job.
        raycast_is_running() {
          /usr/bin/lsappinfo find bundleid=com.raycast.macos 2>/dev/null | grep -q .
        }

        # notify <event> <name> <extension source directory>
        notify() {
          local encoded
          encoded=$(node -e 'process.stdout.write(encodeURIComponent(process.argv[1]))' "$3") \
            || return 1
          /usr/bin/open -g -b com.raycast.macos "raycast://cli/$2/$1?cwd=$encoded&info="
        }

        ensure_fork() {
          if [ ! -e "$fork/.git" ]; then
            mkdir -p "$(dirname "$fork")" || return 1
            # Blobless and left unchecked-out: this is a 2,800-extension monorepo
            # and every worktree scopes itself with a sparse cone. The fork costs
            # about 40M this way.
            timeout 900 git clone --quiet --filter=blob:none --no-checkout \
              "$fork_url" "$fork" || return 1
            # An argument-less cone matches the root files and nothing else, which
            # is what the clone itself wants: the worktrees hold the extensions.
            # Set before the checkout, or git materialises all 2,800 of them.
            git -C "$fork" sparse-checkout set --cone || return 1
            # GitHub still has this fork's default branch pointed at a feature
            # branch, so a fresh clone does not land on main by itself.
            git -C "$fork" checkout --quiet main || return 1
          fi

          git -C "$fork" remote get-url upstream >/dev/null 2>&1 \
            || git -C "$fork" remote add upstream "$upstream_url" || return 1

          # worktrunk's `sync` and `extension` aliases fetch upstream/main. Without
          # these two the fetch backfills blobs for every file touched across
          # upstream history instead of taking commits and trees alone.
          git -C "$fork" config remote.upstream.promisor true
          git -C "$fork" config remote.upstream.partialclonefilter blob:none
        }

        # install_extension <name> <branch> <worktree>
        install_extension() {
          local name=$1 branch=$2 worktree=$3
          local directory="$worktree/extensions/$name"
          local stamp="$stamp_root/$name"

          if [ ! -e "$worktree/.git" ]; then
            git -C "$fork" fetch --quiet origin \
              "+refs/heads/$branch:refs/remotes/origin/$branch" || return 1
            # Never -B: the local branch is where unpushed work sits, and resetting
            # it to the remote would throw that away.
            if git -C "$fork" show-ref --verify --quiet "refs/heads/$branch"; then
              git -C "$fork" worktree add --quiet "$worktree" "$branch" || return 1
            else
              git -C "$fork" worktree add --quiet --track -b "$branch" \
                "$worktree" "origin/$branch" || return 1
            fi
          fi
          git -C "$worktree" sparse-checkout set --cone "extensions/$name" || return 1

          [ -f "$directory/package.json" ] || return 1

          # Rebuilding on every switch would mean an npm install and a tsc run for
          # each tracked extension, so gate on the commit the install was built
          # from. Uncommitted work in the worktree is deliberately not a trigger:
          # that is what `wt dev` is for, and its build overwrites the same
          # directory. A commit is what makes a change part of the installed
          # version.
          #
          # 2 rather than 0 so the caller can tell "already installed" from
          # "just built". Both are success, but only one has anything to
          # register, and registering means deep links that bring Raycast to
          # the front — on every switch, for an extension that had not changed.
          #
          # The trade is that an extension Raycast forgets while its directory
          # survives stops being re-registered. Removing the stamp forces it.
          local head
          head=$(git -C "$worktree" rev-parse HEAD) || return 1
          if [ "$(cat "$stamp" 2>/dev/null)" = "$head" ] \
            && [ -f "$install_root/$name/package.json" ]; then
            return 2
          fi

          # npm, never pnpm, and `ci` over `install`: Raycast CI accepts only
          # package-lock.json, and install rewrites the lockfile, which would land
          # as an unrelated diff on the one file review polices hardest. Fall back
          # to install when there is no lockfile to honour yet, i.e. a brand-new
          # extension.
          if [ -f "$directory/package-lock.json" ]; then
            npm ci --prefix "$directory" --no-audit --no-fund || return 1
          else
            npm install --prefix "$directory" --no-audit --no-fund || return 1
          fi

          # No --output, so this writes to $install_root/$name and fires
          # build-refresh itself. -e dist is the store-submission build: minified,
          # and type-checked on the way through, which is the same gate the PR
          # will face.
          (cd "$directory" && ./node_modules/.bin/ray build -e dist) || return 1

          mkdir -p "$stamp_root" && printf '%s' "$head" > "$stamp"
        }

        ensure_fork || exit 1

        status=0
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: branch:
            let
              quotedName = lib.escapeShellArg name;
              quotedDirectory = lib.escapeShellArg "${worktreeFor branch}/extensions/${name}";
            in
            ''
              install_extension ${quotedName} ${lib.escapeShellArg branch} \
                ${lib.escapeShellArg (worktreeFor branch)}
              case $? in
              0)
                if raycast_is_running; then
                  notify start ${quotedName} ${quotedDirectory}
                  sleep 1
                  notify stop ${quotedName} ${quotedDirectory}
                else
                  echo "raycast: built ${name}, but Raycast is not running to register it"
                fi
                ;;
              2) ;;
              *)
                echo "raycast: could not install ${name} from ${branch}" >&2
                status=1
                ;;
              esac
            ''
          ) tracked
        )}
        exit $status
      '';
in
{
  home.activation.raycastExtensions =
    lib.hm.dag.entryAfter [ "writeBoundary" ] # bash
      ''
        run ${script} \
          || warnEcho "raycast: fork extensions are not fully installed, see the output above"
      '';
}
