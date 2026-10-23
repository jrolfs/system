# zsh: moving plugins from zinit to Nix

Status: planned, not started. Everything in `dotfiles/home/.zshrc` between the
`<zinit>` markers is the scope.

## Why

zinit does three jobs in `.zshrc`, and Nix can do all of them better for this
repo:

1. **Fetching plugins from GitHub when a shell starts.** Nothing is pinned, so
   two machines can run different plugin versions, a new machine's first shell
   needs the network, and prezto's `atclone` clones prezto-contrib over
   `git@github.com`, which fails on a machine whose SSH key isn't set up yet.
   As flake inputs or nixpkgs packages they are pinned by `flake.lock`, move
   with `nix-update`, and are already on disk before the first shell.
2. **Deferring work until after the prompt** (`wait lucid`). `zsh-defer` (in
   nixpkgs) does the same without a plugin manager.
3. **Running hooks at the right moment**, using `zdharma-continuum/null` as an
   empty plugin to hang an `atload` on. Without zinit these are plain lines,
   deferred where they were deferred.

zinit's caching has already caused real problems: `zinit snippet` copied
local files once and kept sourcing the stale copy, which hid every edit to
`~/.config/zsh/init` and left the encrypted `keys.zsh` in use after the castle
was unlocked. The init files are now sourced directly (commit `2ddaf7d`).

## Shape

Keep `.zshrc` hand-written. Replace the zinit block with a Nix-generated
`~/.config/zsh/plugins.zsh` that `.zshrc` sources, following the precedent of
`modules/home/shared/nix-commands.nix`, which generates `~/.config/zsh/init/nix.zsh`.
The generated file sources store paths directly, so there is no fetching and
nothing to cache.

Home-manager's `programs.zsh` (which has a prezto module) is the larger
alternative. It would generate the whole `.zshrc`, which changes how the shell
config is written rather than just where plugins come from, so it isn't
needed for this.

## Inventory

| zinit line | Replacement |
|---|---|
| `sorin-ionescu/prezto`, synchronous | `pkgs.zsh-prezto`, sourced directly |
| prezto-contrib via `atclone` over SSH | flake input (`belak/prezto-contrib`, `flake = false`), linked as `contrib` |
| `null` + atuin init and the up/down `bindkey`s | plain lines after prezto (order matters: after its editor module) |
| `ajeetdsouza/zoxide` with `has'zoxide'` | `eval "$(zoxide init zsh)"` guarded the same way |
| `null` + `direnv hook zsh` | plain `eval` |
| `null` + `devenv hook zsh` | plain `eval` |
| `null` + `wt config shell init zsh` | plain `eval`, guarded on `wt` |
| `zinit snippet` of `homeshick.sh` | plain `source` (the castle stays) |
| OMZ `gem`, `golang`, `mosh`, `pip` snippets, deferred | `pkgs.oh-my-zsh` or a pinned input, those four files, via `zsh-defer` |
| `zsh-users/zsh-completions`, deferred | `pkgs.zsh-completions` on `fpath` |
| `ryutok/rust-zsh-completions`, deferred | flake input on `fpath` |
| `andsens/homeshick` completions | the castle's `completions/` on `fpath` |
| `bobthecow/launchctl-completion` | flake input, sourced on macOS only |
| `ahmetb/kubectx`, deferred | the nixpkgs `kubectx` package's completions on `fpath` |
| `null` + `zicompinit`, `zicdreplay`, then `compdef`s | one deferred `compinit`, then the `compdef`s |

## Things to get right

- **Completion setup is the delicate part.** Everything that adds to `fpath`
  must happen before `compinit`. zinit queued `compdef` calls and replayed them
  after (`zicdreplay`); without it, `compdef` simply runs after `compinit`. The
  existing comment in `.zshrc` about `wt` and pnpm explains why those two
  `compdef`s sit where they do, and still applies.
- **Keep the deferral.** Compare startup before and after:

  ```sh
  nix run nixpkgs#hyperfine -- --warmup 3 --runs 20 -N \
    -n before "env ZDOTDIR=$before zsh -i -c exit" \
    -n after  "env ZDOTDIR=$after zsh -i -c exit"
  ```

  with each directory holding a copy of `.zshrc` and `.zshenv`. Baseline on
  adrian after `f14ba88`: about 380 ms. For a per-file breakdown, wrap each
  `source` in `$EPOCHREALTIME` timing (`zmodload zsh/datetime`); that is how
  the 337 ms `gpgconf --launch` regression was found. Note prezto sets
  `NO_CLOBBER`, so append to a log with `>>|`.
- **Don't reintroduce prezto's `ssh` module.** Prezto's `gpg` module loads it,
  which is why `gpg` is no longer in `prezto.zsh`. It repointed
  `SSH_AUTH_SOCK` at a shared symlink and ran `ssh-add` on empty agents; the
  useful parts of the `gpg` module live in `init/gpg.zsh`.
- **Order from the current file matters**: prezto first, then the init files,
  then atuin's bindings after prezto's editor module.
