inputs:

self: super:

let
  # Pin packages whose current-revision build isn't in the binary cache yet.
  # `pin` prints the live cache status on each rebuild (see pin.nix) so we know
  # when a pin is safe to remove. The mise pin was dropped 2026-08-12 once
  # cache.nixos.org caught up (the helper reported it safe to remove).
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

  # azure-cli depends on fabric, which nixpkgs marks broken against invoke 3
  # (nixpkgs moved to invoke 3.0.3 by 2026-10-24). allowBroken turns that into
  # a failed build rather than an evaluation error. The previous lock's
  # nixpkgs built it, and the warning below says when current nixpkgs has a
  # cached azure-cli again.
  azure-cli = pin {
    name = "azure-cli";
    rev = "d54020a6ac3211e9f4201631bdf67678818c0cdf";
    sha256 = "0znah7yvspa2dvaf0nb8dgm3lw7qd3n962a8zlqd47j5z55p5m2a";
  };

  # mcp-nixos runs its pytest suite at build time. `test_read_text_file`
  # picks an arbitrary small text file out of the live /nix/store, reads it,
  # and asserts the output contains no "Error" — but plenty of store files
  # legitimately contain that substring (e.g. highlight.pack.js's minified
  # JS: SyntaxError, etc.), so the test fails non-deterministically depending
  # on which store path it happens to land on. The read itself works fine;
  # the assertion is just naive. Drop this once upstream fixes the test.
  #
  # Pinned as well: as of the 2026-10-24 nixpkgs, fastmcp 3.4.7 imports
  # `McpError`, which mcp 2.2.0 renamed to `MCPError`, so mcp-nixos fails its
  # import check. NixOS/nixpkgs#563493 (fastmcp 4.0.10) should fix it. Unlike
  # recode below this is a build failure, so a cached current build does mean
  # it's fixed, and pin's warning is the signal to drop it.
  mcp-nixos = (pin {
    name = "mcp-nixos";
    rev = "d54020a6ac3211e9f4201631bdf67678818c0cdf";
    sha256 = "0znah7yvspa2dvaf0nb8dgm3lw7qd3n962a8zlqd47j5z55p5m2a";
  }).overridePythonAttrs (old: {
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
  #
  # Two patches until upstream catches up. Both are diffs against 1.17.2, so a
  # bump of the input means regenerating or dropping them.
  #
  # pr-77 is tawanorg/claude-sync#77 (sjalife, head 6532402) merged onto main.
  # Without it, a session transcript appended on two machines is a "conflict"
  # rather than a fast-forward, history.jsonl is last-writer-wins, and .conflict
  # copies get uploaded to every other machine. The maintainer has chosen to
  # land it first (#91) but hadn't reviewed it as of 2026-10-24.
  #
  # conflict-copy-loop is ours. A pull that parks the remote copy as .conflict
  # leaves the original's state as it was, so every following pull parks
  # another identical copy: 791 of them from 29 files on ala in October. #77
  # fixes that for transcripts only. The patch stops it for every file by
  # recording identical content as resolved and skipping a copy the newest one
  # already holds.
  claude-sync = super.buildGoModule {
    pname = "claude-sync";
    version = "1.17.2";
    src = inputs.claude-sync;
    patches = [
      ./claude-sync/pr-77-multi-machine-sync.patch
      ./claude-sync/conflict-copy-loop.patch
    ];
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
      # allowed to reach the network. Regenerate after changing bun.lock:
      # `bun install` in the source directory, then take the hash nix reports
      # when it rebuilds.
      #
      # One hash per system, not one hash. What bun writes into node_modules
      # differs by host even from an identical lockfile, so a darwin-only hash
      # failed the first NixOS build with a mismatch. A system missing from
      # this set is better as a readable error than as a mismatch three
      # derivations deep, which is how this one surfaced.
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
        outputHash =
          let
            hashes = {
              aarch64-darwin =
                "sha256-JkS6JWjXOf9coNB61yD+JvPWOwAxooBCAYSanpIL00g=";
              x86_64-linux =
                "sha256-sipNQconaJ2WCSRlsAOwp4AGJLHe4AnI+gPGoZdOXLA=";
            };
            inherit (super.stdenv.hostPlatform) system;
          in
          hashes.${system} or (throw
            ("claude-helpers has no node_modules hash for ${system}; "
              + "build it there and record the hash nix reports"));
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

  # Build one of this repo's own single-file Rust tools.
  #
  # The tools it builds are a few hundred lines of POSIX calls each (xattrs,
  # resource forks, FinderInfo), with no dependency beyond libc, so they are
  # compiled by a bare `rustc` rather than through Cargo. That skips a
  # Cargo.toml, a lock file and a vendored dependency tree per tool, and keeps
  # the derivation the same shape the `$CC` one-liners had. The cost is the
  # rustc closure, which is deliberate: every tool goes through here so they
  # cannot drift onto different compilers.
  #
  # Three of the flags are load-bearing under nix and none of them are
  # obvious, which is the other reason this is centralised:
  #
  #   --edition             bare rustc defaults to the 2015 edition, because
  #                         there is no Cargo.toml for it to read one from
  #   --crate-name          rustc otherwise derives the crate name from the
  #                         source *file name*, which here is a store path, so
  #                         the store hash lands in every mangled symbol
  #   --remap-path-prefix   panic locations embed file!(), which is that same
  #                         store path
  #
  # Without the last two, nix finds the hash while scanning the binary and
  # records the .rs source as a runtime dependency of the tool. Each flag alone
  # still leaves one copy behind (symbols vs. panic strings), so both are
  # needed to keep the closure to a single path.
  # A library crate for the tools above to share, built the same bare way. An
  # rlib needs no Cargo either: `--crate-type=rlib` here, `--extern` there.
  rustLibrary = { name, src, edition ? "2021" }:
    let crateName = builtins.replaceStrings [ "-" ] [ "_" ] name;
    in
    super.stdenv.mkDerivation {
      inherit name;
      dontUnpack = true;
      nativeBuildInputs = [ super.rustc ];
      passthru = { inherit crateName; };
      # An rlib is an ar archive carrying a .rmeta member, and the default
      # fixup phase strips it right back out, leaving a file that only fails
      # at the point something tries to link against it.
      dontStrip = true;
      installPhase = ''
        mkdir -p $out/lib
        rustc --edition ${edition} -O --crate-type=rlib \
          --crate-name ${crateName} \
          --remap-path-prefix ${src}=${name}.rs \
          -o $out/lib/lib${crateName}.rlib ${src}
      '';
    };

  # `program` defaults to `name` and exists for the one tool whose binary has
  # to be called something other than its derivation: the icon-customizer
  # wrapper installs as `icon-customizer`, which is already the name of the
  # shell script it runs.
  rustTool = { name, src, program ? name, edition ? "2021", flags ? [ ], libraries ? [ ] }:
    super.stdenv.mkDerivation {
      inherit name;
      dontUnpack = true;
      nativeBuildInputs = [ super.rustc ];
      installPhase = ''
        mkdir -p $out/bin
        rustc --edition ${edition} -O \
          --crate-name ${builtins.replaceStrings [ "-" ] [ "_" ] name} \
          --remap-path-prefix ${src}=${name}.rs \
          ${super.lib.concatMapStringsSep " "
            (library: "--extern ${library.crateName}=${library}/lib/lib${library.crateName}.rlib")
            libraries} \
          ${super.lib.escapeShellArgs flags} \
          -o $out/bin/${program} ${src}
      '';
      meta.mainProgram = program;
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
