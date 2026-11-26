# Homebrew determinism

Parked notes on pinning cask versions: what Homebrew can actually do, why it
buys much less than it looks like it should, and what to do instead.

Companion docs: [MIGRATION.md](MIGRATION.md), [BACKPORT.md](BACKPORT.md),
[SECRETS.md](SECRETS.md).

Numbers below were measured on 2026-08-23 against the 57 casks in
`modules/darwin/homebrew.nix`.

## The problem

`homebrew.onActivation.upgrade = true`, so every switch takes whatever version
the cask API is currently serving. Nothing in this repo records which version
that was. Raycast went 1.x → 2.x on `ala` with no change to the flake — a major
version bump arriving as a side effect of an unrelated rebuild, which is exactly
the class of thing the migration to flakes was supposed to eliminate.

## What `brew pin` actually does

`brew pin` **does** support casks, contrary to what's commonly claimed:

```
Usage: brew pin [--formula] [--cask] installed_formula|installed_cask [...]
```

Verified live (pinned, listed, unpinned). But note Homebrew's own caveat in that
same help text:

> Pinned casks with `auto_updates true` may update themselves outside Homebrew.

And there is no nix-darwin option for it. A pin is mutable per-machine state in
`$(brew --prefix)`, invisible to the flake — the same category of thing as the
homeshick castles being migrated away from. Adding it would mean a `brew pin`
loop in an activation script, i.e. reintroducing imperative state to buy
determinism.

## Why pinning buys so little

Three independent reasons, in increasing order of how fundamental they are.

**1. 45 of 57 casks self-update.** `auto_updates true` means the app ships its
own updater and replaces its own bundle. Homebrew is not in that loop, so
neither is nix. A pin on any of those 45 is theatre — and this is also why
`onActivation.upgrade = true` isn't the thing moving them: `brew upgrade` skips
`auto_updates` casks unless `--greedy` (nix-darwin exposes this as per-cask
`greedy`, defaulting to `homebrew.greedyCasks`). They update themselves.

**2. The recipe is a moving target.** `brew bundle` reads the cask definition
from whatever the API is serving. Pinning an installed version doesn't pin the
definition that produced it.

**3. There is no artifact store.** This is the fundamental one. A cask is a
vendor URL plus a sha256. Pin an old version and the vendor eventually retires
the URL — at which point the pin is unbuildable and there is nowhere else to get
the bits. nixpkgs fixed-output derivations are backed by cache.nixos.org, so an
old pin stays materialisable for years. Homebrew has no equivalent, and this
cannot be fixed from our side.

`brew extract` doesn't help either — it's formula-only (`brew extract [--version=]
formula tap`). The practical downgrade path for a cask is to check out
homebrew-cask at the revision that carried the version you want and
`brew install --cask <path/to/cask.rb>`, which lands in problem 3 as soon as the
vendor URL is gone.

## nix-homebrew

[`github:zhaofengli/nix-homebrew`](https://github.com/zhaofengli/nix-homebrew)
pins Homebrew itself and its taps as flake inputs. With `mutableTaps = false` it
sets `HOMEBREW_NO_AUTO_UPDATE=1`, plus `HOMEBREW_NO_INSTALL_FROM_API=1` when
homebrew-core is among the pinned taps.

So it solves problem 2 — recipes become flake inputs with a lock entry. It does
nothing for 1 or 3. It is not currently an input here; the cost is bumping those
inputs by hand and carrying a local checkout of homebrew-cask, which is large.
Worth revisiting only if recipe drift specifically starts causing trouble.

## Where determinism is actually achievable

Only the 12 casks *without* `auto_updates` can be pinned meaningfully at all.
Nine of those already exist in this flake's nixpkgs, and two more are in a tap
we own:

| cask | cask version | nixpkgs |
| --- | --- | --- |
| `font-fira-code-nerd-font` | 3.5.1 | `nerd-fonts.fira-code` |
| `font-hack-nerd-font` | 3.5.1 | `nerd-fonts.hack` |
| `font-ibm-plex` | 6.4.1 | `ibm-plex` |
| `font-iosevka` | 34.8.1 | `iosevka-bin` |
| `font-iosevka-slab` | 34.8.1 | `iosevka-bin.override { variant = "Slab"; }` |
| `font-jetbrains-mono` | 2.304 | `jetbrains-mono` (2.304) |
| `font-jetbrains-mono-nerd-font` | 3.5.1 | `nerd-fonts.jetbrains-mono` |
| `1password-cli` | 2.39.0 | `_1password-cli` (2.34.1 — lags) |
| `kitty` | 0.48.2 | `kitty` (0.48.2) |
| `jrolfs/tap/lingon-pro` | 10.2.6 | own tap, we control the recipe |
| `jrolfs/tap/unite-pro` | 1.7.0.1 | own tap, we control the recipe |
| `maxon` | 2026.5.0 | — |

Every attribute above was evaluated against `darwinConfigurations.ala.pkgs`, so
the names are current, not remembered.

`maxon` is the only cask where pinning is both meaningful and unsolved.

## Recommendation

1. **Move the 7 fonts to `fonts.packages`.** Real determinism, cache-backed, no
   Homebrew involvement, and fonts have none of the placement problems below.
   This is the whole win available here and it's cheap.
2. **Consider `1password-cli` and `kitty` separately.** `1password-cli` lags in
   nixpkgs. And GUI apps from nixpkgs surface under `/Applications/Nix Apps/`,
   which breaks two things that scan or hardcode `/Applications`: the icon
   customizer's `fd` pass in `modules/darwin/icons.nix`, and the Karabiner
   Left-Option+Tab kitty toggle.
3. **Let the other 45 float.** They self-update no matter what this repo says.
   Pinning them adds ceremony and mutable per-machine state without buying
   determinism.
4. **Skip `nix-homebrew`** until recipe drift is a demonstrated problem.
5. **`maxon`:** accept the drift, or vendor it into `jrolfs/tap` where we own the
   recipe and can hold the URL and sha256 ourselves.

The honest summary: Homebrew is the escape hatch for software that can't be
expressed in nixpkgs, and giving up version determinism is the price of the
hatch. The productive move is shrinking what goes through it, not trying to make
it deterministic.
