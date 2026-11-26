{
  description = "Jamie's machines — cross-host nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # nixpkgs/master, for packages that need a bleeding-edge build via the
    # `masterPkgs` overlay (e.g. spicetify-cli). Bump: nix flake update
    # nixpkgs-master. Replaces the old npins-based master pin.
    nixpkgs-master.url = "github:NixOS/nixpkgs";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning, used by the NixOS hosts. Pairs with
    # nixos-anywhere, which runs disko on the target before installing: the
    # layout is config rather than a one-time manual act, and disko generates
    # the `fileSystems` entries that would otherwise come from
    # hardware-configuration.nix.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Glide packaged for nix, plus a home-manager module built on
    # home-manager's own mkFirefoxModule factory. The packages are not used to
    # install Glide (see modules/home/browsers.nix for why Homebrew still owns
    # that); the module is what we're after, and glide-browser-bin-unwrapped is
    # the source the Glide Developer bundle is derived from.
    glide = {
      url = "github:glide-browser/glide.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Bootstrap repo — provisions a new machine, and provides the `bootstrap`
    # CLI whose `secrets` subcommands read the committed `op://` manifest. A
    # real flake (not `flake = false`) because we consume its
    # `packages.bootstrap` output.
    #
    # Note the manifest is baked into the store copy, so the CLI on PATH carries
    # the manifest as of this input's lock. Run it from inside a bootstrap
    # checkout to use that working tree's manifest instead; otherwise
    # `nix flake update bootstrap` to pick up new references.
    bootstrap = {
      url = "github:jrolfs/bootstrap";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Neovim config — separate repo, consumed as a source tree.
    neovim-config = {
      url = "github:jrolfs/neovim";
      flake = false;
    };

    # Theme / plugin source trees that land in $HOME via home-manager
    # source = "${inputs.X}". All flake = false.
    kitty-gruvbox-material = {
      url = "github:jrolfs/gruvbox-material-kitty";
      flake = false;
    };
    # kitty kittens, bound in kitty/bindings.conf: grab on ctrl+s>} (vim-modal
    # scrollback selection, configured by kitty/grab.conf) and smart-scroll on
    # ctrl+shift+{k,j,u,d} (scrolls the pager when one is running, the buffer
    # otherwise). Both were `dot` castle submodules and are pinned here at the
    # same upstream commits that castle carried — no local patches.
    kitty-grab = {
      url = "github:yurikhan/kitty_grab";
      flake = false;
    };
    kitty-smart-scroll = {
      url = "github:yurikhan/kitty-smart-scroll";
      flake = false;
    };
    tridactyl-gruvbox-material = {
      url = "github:jrolfs/gruvbox-material-tridactyl";
      flake = false;
    };
    spicetify-gruvbox-material = {
      url = "github:whiterqbbit/spicetify-gruvbox-material";
      flake = false;
    };
    zinit = {
      url = "github:zdharma-continuum/zinit";
      flake = false;
    };

    # zshcs — Zsh LSP server, built by the overlay (overlays/default.nix).
    # Not in nixpkgs; was previously pinned via npins. flake = false so we
    # just get the source tree.
    zshcs = {
      url = "github:yuys13/zshcs";
      flake = false;
    };

    # claude-sync — end-to-end-encrypted sync of Claude Code session state
    # (~/.claude projects/, history, tasks, plans) through an S3-compatible
    # bucket. Not in nixpkgs; built by the overlay from this source tree.
    claude-sync = {
      url = "github:tawanorg/claude-sync";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, ... }:
    let
      userName = "jamie";

      mkDarwin = hostname: system: nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs hostname userName; };
        modules = [
          ./modules/darwin
          ./hosts/${hostname}
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs hostname userName; };
            home-manager.users.${userName} = import ./modules/home;
            home-manager.sharedModules = [ ./modules/home/darwin.nix ];
          }
        ];
      };

      forSystems = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ];

      mkNixos = hostname: system: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs hostname userName; };
        modules = [
          ./modules/nixos
          ./hosts/${hostname}
          inputs.disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs hostname userName; };
            home-manager.users.${userName} = import ./modules/home;
            home-manager.sharedModules = [ ./modules/home/linux.nix ];
          }
        ];
      };
    in
    {
      darwinConfigurations.ala = mkDarwin "ala" "aarch64-darwin";
      darwinConfigurations.adrian = mkDarwin "adrian" "aarch64-darwin";
      # darwinConfigurations.newt = mkDarwin "newt" "aarch64-darwin";  # retired

      nixosConfigurations.irulan = mkNixos "irulan" "x86_64-linux";  # phase 2

      # Node + pnpm for editing the Glide browser's TypeScript config in
      # dotfiles/home/.config/glide, whose .envrc is `use flake .#glide` —
      # nix searches up from there and finds this flake.
      #
      # Deliberately not a nested flake in that directory: nix resolves one to
      # `git+file://…?dir=dotfiles/home/.config/glide`, so this whole repo gets
      # copied to the store either way, and a second flake.lock and second
      # nixpkgs would buy nothing for a two-package shell.
      devShells = forSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          glide = pkgs.mkShell {
            packages = [ pkgs.nodejs_24 pkgs.pnpm ];
          };
        });
    };
}
