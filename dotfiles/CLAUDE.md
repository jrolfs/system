# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

The dotfile tree for the nix flake that deploys to `~/.config/system`. Files under `home/` mirror `$HOME`, and **home-manager** links them there from declarations in `modules/home/` at the repo root.

This tree was the `dot` and `macos` homeshick castles before the flake migration, subtree-merged with their history. `private` is the only remaining castle: git-crypt, cloned by bootstrap, still reached through `$HOMESHICK_KINGDOM`. [MIGRATION.md](../MIGRATION.md) at the repo root is the source of truth for the migration and its gotchas.

## Before editing files here

**A tracked file is not a linked file.** homeshick linked whatever sat in the castle. Here every path needs a declaration in `modules/home/`, and a tracked file nobody declared is simply absent on the machine, which reads as a broken feature rather than a missing symlink. Adding a file under `home/` is only half the change.

**Not every path in `$HOME` has a file here.** Some are generated from nix options, so there is nothing in this tree to edit: `.zshrc.darwin` (the `nix-switch`, `nix-rebuild`, `icn`, and `mkbk` aliases) comes from `modules/home/darwin.nix`, atuin from `modules/home/atuin.nix`, and direnv from `programs.direnv`. Most other tools are still lift-and-shift files in this tree.

**Whether an edit takes effect on save depends on the path.** Most files are copied into the nix store and need a rebuild. Others are `mkOutOfStoreSymlink`ed back to this tree and are live on save. Check rather than assume:

```bash
readlink -f ~/.config/kitty
# /nix/store/…        store copy, rebuild with nix-switch
# ~/.config/system/…  out-of-store, edit in place
```

Measured at the time of writing. Live: `.config/glide`, `.config/zsh`. Store copies: `.zshrc`, `.config/kitty`, `.config/git/config`, `.hammerspoon/init.lua`. Two more link somewhere other than this tree: `~/.config/nvim` to a clone at `~/Developer/Sources/jrolfs/neovim`, and `~/.config/karabiner` to `karabiner/` at the repo root.

## Structure

- `home/`: mirrors `$HOME`, including `home/Library` and `home/Documents` for macOS-specific paths
- `home/.config/`: XDG config home, organized per application
- `duckduckgo/`, `slack/`: app configs that are neither XDG nor linked

There are no git submodules. The themes and plugins that used to be submodules are flake inputs at the repo root.

## Key Configurations

**Shell (zsh):** entry points are `home/.zshenv` → `home/.zprofile` → `home/.zshrc` → `home/.zlogin`. Modular config lives in `home/.config/zsh/`: `init/`, `completions/`, and a file per tool (`mise.zsh`, `starship.zsh`, `prezto.zsh`, `kitty-tabs.zsh`). Machine-specific env files use the pattern `env.<hostname>`. `.zshrc` is a lifted file, which leaves `programs.zsh.initContent` inert, so zsh additions belong here rather than in nix.

**Git:** config at `home/.config/git/config`, linked as-is rather than generated from `programs.git`. Uses delta as pager, GPG signing by default, git-duet for pairing.

**Kitty terminal:** `home/.config/kitty/` with separate files for bindings, diff, and grab, plus `sessions/`.

**Glide browser:** TypeScript config at `home/.config/glide/`. Its `.envrc` runs `use flake .#glide` against the root flake, so there is no devbox.json. The directory is linked out-of-store so the browser can write back into this tree, which is how `:toolbar_export` in `toolbar.ts` records the toolbar layout.

## Conventions

- **Indentation:** 2 spaces, LF line endings, UTF-8 (see `.editorconfig`)
- **Runtime versions:** managed via **mise**, activated from `.zprofile`
- **XDG compliance:** configs use `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME`
- **JS/TS linting:** oxlint (`.oxlintrc.json` in this directory) prefers `type-imports` with inline style, disallows default exports, uses `^_` for unused vars
- **JS/TS formatting:** oxfmt (`.oxfmtrc.json` in this directory)

## Working with This Repo

There is no test suite or CI. Changes are made by editing config files and committing. Applying them means `nix-switch` for store-linked paths and nothing at all for out-of-store ones; for shell config you can also re-source the file.

When editing zsh config, be aware of the load order: `.zshenv` (always) → `.zprofile` (login) → `.zshrc` (interactive) → `.zlogin` (login, after `.zshrc`). Environment variables and path setup belong in `.zshenv`/`.zprofile`; interactive features (aliases, completions, keybindings) belong in `.zshrc` or the modular files it sources from `home/.config/zsh/`.
