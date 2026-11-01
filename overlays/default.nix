inputs:

self: super:

let
  # Pin packages whose current-revision build isn't in the binary cache yet.
  # `pin` prints the live cache status on each rebuild (see pin.nix) so we know
  # when a pin is safe to remove. Currently no active pins — the mise pin was
  # dropped 2026-08-12 once cache.nixos.org caught up (the helper reported it
  # safe to remove). Kept imported for the next time a build lags the cache.
  pin = import ./pin.nix super;

  # Install packages from the `nixpkgs/master` branch via `masterPkgs`,
  # pinned by the `nixpkgs-master` flake input (bump with
  # `nix flake update nixpkgs-master`). Replaces the previous npins-based
  # pin now that everything is flake-managed.
  #
  # NOTE: packages installed from `master` are often not cached in
  # Cachix, so install from `masterPkgs` may often result in building
  # a bunch of stuff from source.
  masterPkgs = import inputs.nixpkgs-master {
    localSystem = super.stdenv.hostPlatform.system;
    inherit (super) config;
  };
in

{
  spicetify-cli = masterPkgs.spicetify-cli;

  # mcp-nixos runs its pytest suite at build time. `test_read_text_file`
  # picks an arbitrary small text file out of the live /nix/store, reads it,
  # and asserts the output contains no "Error" — but plenty of store files
  # legitimately contain that substring (e.g. highlight.pack.js's minified
  # JS: SyntaxError, etc.), so the test fails non-deterministically depending
  # on which store path it happens to land on. The read itself works fine;
  # the assertion is just naive. Drop this once upstream fixes the test.
  mcp-nixos = super.mcp-nixos.overridePythonAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [ "test_read_text_file" ];
  });

  # recode 3.7.16 is broken on aarch64-darwin as of the 2026-09 nixpkgs bump.
  # Its own test suite catches it — ten round-trip conversions fail and the
  # harness dies with `Segmentation fault: 11` — so the build fails honestly
  # rather than shipping something broken.
  #
  # Do *not* "fix" this with `doCheck = false`. Measured with the checks off:
  # the resulting `recode utf8..ascii` aborts with SIGABRT after printing
  # "Charset WINDOWS-874 already exists and is not CP874", and fortune, which
  # links it, then prints nothing at all while still exiting 0. Disabling the
  # tests converts a loud build failure into a silently useless binary.
  #
  # So pin the whole package to the last nixpkgs revision where it worked.
  # Deliberately not via ./pin.nix: that helper reports when a pin is safe to
  # remove by checking the binary cache, and cache availability says nothing
  # about whether this is fixed — it would advise removing the pin at exactly
  # the moment doing so would quietly break fortune again. Re-test by hand
  # (`recode utf8..ascii <<< 'héllo'` should round-trip, not abort) before
  # dropping this.
  recode =
    let
      lastWorking = import
        (builtins.fetchTarball {
          url = "https://github.com/NixOS/nixpkgs/archive/d482ef84049d9b7276b83a06e4e4d76983830097.tar.gz";
          sha256 = "sha256-we5zDEFfn8TgzeWKjKDMIjeQZ59omEPl23NIF+13/ys=";
        })
        {
          localSystem = super.stdenv.hostPlatform.system;
          inherit (super) config;
        };
    in
    lastWorking.recode;

  # worktrunk's test suite includes two tests that probe the OS process table
  # (reading its own PID and a spawned child `sh`), which the Nix build sandbox
  # on darwin doesn't expose — they panic with "own pid must be readable from
  # the process table" / "child sh must be visible to the probe". The package
  # already skips other sandbox-hostile tests via checkFlags; append these two.
  # Drop once upstream gates them on process-table availability.
  worktrunk = super.worktrunk.overrideAttrs (old: {
    checkFlags = (old.checkFlags or [ ]) ++ [
      "--skip=shell::utils::tests::test_process_name_and_ppid_self"
      "--skip=shell::utils::tests::test_probe_reports_invoked_name_for_sh"
    ];
  });

  # zshcs — Zsh LSP server (github:yuys13/zshcs), not in nixpkgs. Pinned via
  # the `zshcs` flake input (flake = false); bump with `nix flake update zshcs`.
  # Reuses upstream flake.nix's build recipe: a plain buildRustPackage with
  # checks disabled (its tests need a pty unavailable in the Nix sandbox).
  # The server spawns `zsh` at runtime for completions, so wrap it to guarantee
  # zsh is on PATH even when launched by a GUI editor with a minimal environment
  # (--suffix keeps the user's own environment/commands ahead of it).
  zshcs = super.rustPlatform.buildRustPackage {
    pname = "zshcs";
    version = "0.1.0";
    src = inputs.zshcs;
    cargoLock.lockFile = "${inputs.zshcs}/Cargo.lock";
    doCheck = false;
    nativeBuildInputs = [ super.makeWrapper ];
    postInstall = ''
      wrapProgram $out/bin/zshcs \
        --suffix PATH : ${super.lib.makeBinPath [ super.zsh ]}
    '';
  };

  # claude-sync — end-to-end-encrypted sync of Claude Code session state
  # (github:tawanorg/claude-sync). Not in nixpkgs, and upstream ships no
  # license, so it couldn't be upstreamed as-is. The npm package of the same
  # name is only a prebuilt-binary shim; this builds from the Go source pinned
  # by the `claude-sync` flake input (bump with `nix flake update claude-sync`).
  claude-sync = super.buildGoModule {
    pname = "claude-sync";
    version = "0.4.0";
    src = inputs.claude-sync;
    vendorHash = "sha256-VLqVk5bhM+WoEbP+agFpm1LjzI2qFWlWQZB8yV2vbOU=";
    subPackages = [ "cmd/claude-sync" ];
    meta.mainProgram = "claude-sync";
  };

  # The Claude Code helper scripts kept in dotfiles/home/.claude/bin, built into
  # a package so they land on PATH with the rest of the profile instead of
  # needing ~/.claude/bin added to it.
  #
  # The shebangs are the other half of the reason to package them. `env python3`
  # would otherwise find /usr/bin/python3, a Command Line Tools shim that
  # prompts to install Xcode on a machine that hasn't and is gone entirely on
  # some macOS releases, and `env bun` would find nothing at all: bun is a
  # dependency of these scripts, not something the machine is expected to have.
  claude-helpers =
    let
      source = ../dotfiles/home/.claude/bin;

      # Only the two files that decide what gets installed, so editing a script
      # doesn't invalidate the fetch below and send it back to the network.
      manifest = super.runCommandLocal "claude-helpers-manifest" { } ''
        install -d $out
        install -m644 ${source}/package.json ${source}/bun.lock $out/
      '';

      # Dependencies as a fixed-output derivation, the one place in this build
      # allowed to reach the network. bun.lock pins what lands here, so the hash
      # changes when the lockfile does and at no other time. Regenerate both
      # together: `bun install` in the source directory, then take the hash nix
      # reports when it rebuilds.
      modules = super.stdenvNoCC.mkDerivation {
        name = "claude-helpers-node-modules";
        src = manifest;
        nativeBuildInputs = [ super.bun ];
        dontFixup = true;
        buildPhase = ''
          export HOME=$TMPDIR
          export BUN_INSTALL_CACHE_DIR=$TMPDIR/cache
          bun install --frozen-lockfile --ignore-scripts --no-progress
        '';
        installPhase = "cp -R node_modules $out";
        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-JkS6JWjXOf9coNB61yD+JvPWOwAxooBCAYSanpIL00g=";
      };
    in
    super.runCommandLocal "claude-helpers"
    { nativeBuildInputs = [ super.bun super.python3 ]; }
    ''
      install -d $out/bin
      find ${source} -maxdepth 1 -type f ! -name '*.ts' ! -name '*.tsx' \
        ! -name '*.json' ! -name 'bun.lock' -exec install -m755 -t $out/bin {} +

      # One bundle per command, so nothing has imports to resolve at runtime.
      # The sources are copied out of the store first because bun finds
      # node_modules by walking up from the file that imports it, and the store
      # path it would walk up from is not ours to put anything in.
      cp -R ${source} source
      cp -R ${modules} node_modules
      chmod -R u+w source node_modules

      # Ink reaches for react-devtools-core in the DEV path nothing here takes,
      # and the bundler resolves that import whether or not it runs. A stub
      # satisfies it without carrying the devtools.
      install -d node_modules/react-devtools-core
      echo '{"name":"react-devtools-core","version":"0.0.0","main":"index.js"}' \
        > node_modules/react-devtools-core/package.json
      echo 'export default { connectToDevTools: () => {} };' \
        > node_modules/react-devtools-core/index.js

      export HOME=$TMPDIR
      for entry in source/*.ts source/*.tsx; do
        [ -e "$entry" ] || continue
        name=$(basename "$entry")
        bun build "$entry" --target=bun --outfile="$out/bin/''${name%.*}"
      done

      chmod 755 $out/bin/*
      patchShebangs --build $out/bin
    '';

  # Built from source because nixpkgs' mysides unpacks the upstream .pkg from
  # 2015, which is x86_64-only — it dies with "bad CPU type in executable" on
  # an Apple Silicon machine without Rosetta. The source compiles for arm64
  # with nothing but Foundation and CoreServices.
  #
  # It drives LSSharedFileList, deprecated since 10.11 and still the only way
  # to write Finder's sidebar: `sfltool` offers list/clear/reset and nothing
  # that adds an item. Verified working on macOS 26 — `mysides list` returns
  # the same entries decoded by hand out of the FavoriteItems.sfl4 archive.
  # If a release finally removes the API, the fallback is writing that
  # NSKeyedArchiver plist directly, bookmark blobs and all.
  mysides = super.stdenv.mkDerivation {
    pname = "mysides";
    version = "1.0.1-unstable-2024-02-16";

    src = super.fetchFromGitHub {
      owner = "mosen";
      repo = "mysides";
      rev = "355d010b61c4ad36fcdd84b0f9e6ec530369bd1b";
      hash = "sha256-aAZOGeU8lvMPxBIHKbNNe5WVHvSfRpjgnqJ6qV4Jw00=";
    };

    buildPhase = ''
      runHook preBuild
      $CC -fobjc-arc -framework Foundation -framework CoreServices \
        -o mysides src/*.m
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 mysides $out/bin/mysides
      runHook postInstall
    '';

    meta = {
      description = "Manage macOS Finder sidebar favorites";
      homepage = "https://github.com/mosen/mysides";
      platforms = super.lib.platforms.darwin;
      mainProgram = "mysides";
    };
  };

  darwin-zsh-completions = super.runCommandNoCC "darwin-zsh-completions-0.0.0"
    { preferLocalBuild = true; }
    ''
      mkdir -p $out/share/zsh/site-functions
      cat <<-'EOF' > $out/share/zsh/site-functions/_darwin-rebuild
      #compdef darwin-rebuild
      #autoload
      _nix-common-options
      local -a _1st_arguments
      _1st_arguments=(
        'switch:Build, activate, and update the current generation'\
        'build:Build without activating or updating the current generation'\
        'check:Build and run the activation sanity checks'\
        'changelog:Show most recent entries in the changelog'\
      )
      _arguments \
        '--list-generations[Print a list of all generations in the active profile]'\
        '--rollback[Roll back to the previous configuration]'\
        {--switch-generation,-G}'[Activate specified generation]'\
        '(--profile-name -p)'{--profile-name,-p}'[Profile to use to track current and previous system configurations]:Profile:_nix_profiles'\
        '1:: :->subcmds' && return 0
      case $state in
        subcmds)
          _describe -t commands 'darwin-rebuild subcommands' _1st_arguments
        ;;
      esac
      EOF
    '';
}
