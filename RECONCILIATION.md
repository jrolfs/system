# Reconciliation pass: newt castles → macos.flake (2026-09-16)

Newt is damaged and being replaced, so its live homeshick state is the source
of truth for anything not yet migrated. This is the record of the sweep: what
was synced into the flake, what still needs a decision, and what the legacy
repo has that the flake doesn't. Backup of the entire kingdom first:
`~/Backups/homesick-newt-2026-09-16.tar.gz` (3.8G, excludes node_modules /
.direnv / .devbox / .venv; one op daemon socket and macOS xattrs not packed).

Audit scope: every file under `home/` in the `dot` and `macos` castles compared
against `dotfiles/home/` here. Counts: dot 102 identical, 11 drifted castle-side,
10 drifted flake-side (all intentional flake advances), 52 castle-only, 53
flake-only. macos castle: 37 identical, 1 drifted, 28 castle-only (27 of them
`.nixpkgs/`, covered by modules here). The `private` castle is git-crypt
**unlocked** on this machine; its content has no flake mirror by design (see
SECRETS.md), so it was not content-diffed.

## (a) Applied syncs (castle copy was newer, flake already tracked the file)

- `.claude/CLAUDE.md`: adds the Prose and expanded TSDoc guidance sections.
- `.claude/settings.json`: default model `fable` (was `claude-opus-5`).
- `.config/starship.toml`: battery symbols switched to nerd-font glyphs.
- `.config/worktrunk/config.toml`: adds the documented
  `projects."github.com/jrolfs/extensions"` block (sparse-checkout monorepo,
  copy-ignored excludes).
- `.config/zed/settings.json`: diagnostics panel settings, `ui_font_size` 13,
  project-panel `show_diagnostics`, `file_types` + yaml-language-server LSP
  block for GitHub Actions workflows. Note: the live copy also *removed*
  `github-actions` from `auto_install_extensions` (replaced by the
  yaml-language-server schema setup). That removal rode along.
- `.config/zsh/kitty-tabs.zsh`: pinned-title lookup now prefers the deepest
  pinned ancestor and keeps sibling worktrees distinct.
- `.zprofile`: sources `init/keys.zsh` for login shells (kitty session panes,
  editor agent servers) and uses `$ZSH_EXTRA_COMPLETIONS` (defined identically
  in both `.zshenv`s).
- `.zshenv`: surgical merge, not a copy: took the castle's
  `ANTHROPIC_DEFAULT_{OPUS,FABLE}_MODEL=...[1m]` lines, kept the flake's
  intentional removal of `OP_CONFIG_DIR` (BACKPORT.md item 1). The only
  remaining diff between the two copies is that intentional block.
- `.hammerspoon/init.lua` (from the **macos** castle): adds `WhatsApp` to the
  autohide list.

## (b) Mechanical follow-ups (no judgment needed, not yet done)

- Push the neovim castle: 2 unpushed commits (`8d9ae0c`, `4157899`, the
  tree-sitter work), then `nix flake update neovim-config` here and switch
  (the `after/` top-level entry needs it).
- `dot` castle has staged-but-uncommitted work (`.claude/keybindings.json`
  add, completions deletes, the applied-sync sources above). Castle repos were
  read-only for this pass; commit or abandon there as you see fit. The flake
  now carries the content either way.
- `~/.claude/keybindings.json` is castle-tracked but has no flake mirror yet:
  add `dotfiles/home/.claude/keybindings.json` (part of item (f)).

## (c) Needs your decision

- **zsh completions deletions**: the castle staged deletes of
  `.config/zsh/completions/{_gh,_infractl,_kubectl,kitty.zsh}` but the flake
  still ships them (plus `_launchctl`, which the flake's `.zshrc` also covers
  via the `bobthecow/launchctl-completion` zinit plugin). Should the flake drop
  the four (five?) too? Deletions weren't auto-applied.
- **`.config/git/config`**: the castle re-added a second
  `[url "ssh://git@github.com/"] insteadOf` block (line 204, duplicating line
  162). That's the parked "insteadOf duplication" bug; the flake copy is the
  deduplicated one and was left alone. The castle copy should probably lose it
  instead (backport direction).
- **`.config/spicetify/config-xpui.ini`**: castle copy has a spicetify-written
  `[Backup] version = 1.2.99...` stanza (machine-local state). Not applied; the
  flake copy is a seed and the live dir is an out-of-store symlink anyway.
  Decide whether the seed should ever carry a Backup stanza (probably not).
- **`.zshrc`**: castle copy is *behind* (still sources zinit from the homeshick
  path, lacks launchctl-completion). Nothing to take; flagged only because its
  mtime is newer, which makes it look drifted at a glance.
- **kitty theme vendoring**: castle has `.config/kitty/themes/gruvbox-material/`
  as a vendored checkout plus `themes/current.conf`; the flake handles kitty
  theming differently. Confirm the flake's kitty theme path covers what
  `current.conf` selected.
- **`.config/claude/mcp.json` + `~/.claude/bin/claude-mcp-sync`**: castle-only
  today. Decide whether MCP server config should be flake-declared (it pairs
  with the `claude-mcp-sync` script that syncs it into project `.mcp.json`s).

## (d) Backport gaps: legacy `macos` repo → flake

The flake has module counterparts for everything the legacy
`darwin-configuration.nix` imports **except**:

1. **`login-items.nix`** (commits `5d4d88a`, `a5dbd27`): declarative app login
   items via System Events osascript, authoritative list, removal of
   unmanaged items. No flake counterpart at all. The BTM store is SIP-locked,
   so this osascript approach is the only scriptable path (see memory:
   macos-login-items-btm). Port list: CleanShot X, Hammerspoon, Moom,
   PixelSnap 2, Raycast, Resilio Sync, Stay, Velja, FigmaAgent.
2. **`tailscale.nix`** (commit `0cdb82e`): "connect everywhere except at home"
   via a launchd agent driving `tailscale up`/`down` through LocalAPI, gateway
   fingerprinting instead of SSID (CoreLocation redacts SSID). Deliberately
   avoids macOS on-demand VPN (NEOnDemandRule flaps and kills DNS). The commit
   message calls the macOS feature broken; the module is the workaround, not
   the broken attempt. No flake counterpart.
3. **`spotlight.nix`**: Spotlight indexing control (Raycast is the daily
   search). No flake counterpart.
4. **`sonora` overlay (uncommitted in the legacy repo)**: adds `pkgs.sonora`
   via `builtins.getFlake github:sonorahq/sonora/<pinned rev>`, using the
   flake's prebuilt `sonora-bin` output on aarch64-darwin (source builds pull
   the unfree Metal toolchain). In this repo it belongs as a proper flake
   input, not a `getFlake` bridge. Also add the package to the shared or
   host package list.

Not gaps: `135fc28` (legacy nixpkgs submodule bump; this repo pins its own
nixpkgs) and `f43a396` (jrolfs tap update; the tap is declared here in
`homebrew.nix` and the tap content lives in the tap repo. The castle-only
`.local/share/homebrew/taps/jrolfs` local checkout is legacy plumbing; verify
`modules/darwin/tap.nix` doesn't reference it before deleting).

Also castle-only in `macos`: `.gnupg/gpg-agent.conf` (flake manages gpg-agent
in modules/home; verify option parity), `.zshrc.darwin` (flake generates its
own; redesign already planned), `.config/nvim/sessions/dot--macos.vim` (dead,
deletion candidate from the earlier session-file work).

## (e) Castle-only files in `dot` not yet migrated

Cross-reference MIGRATION.md's unlinked list (line ~147) before acting; most
of these are already known there. Grouped by disposition:

**Likely dead, delete-with-the-castle**: `.vintrc.yaml`, `.config/oni/`,
`.config/asdf/` + `.local/share/asdf`, `.config/pry/pryrc`, `.travis/`,
`.synergy/`, `.boot/boot.properties`, `.shfoo/tmux/`, `.rexp/ip`,
`.httpie/config.json`, `.config/zsh/archive/powerlevel.zsh`,
`.local/share/exa-wrapper.sh` (superseded by eza-wrapper),
`.config/nvim/sessions/dot--dot.vim`, `.config/glide/devbox.{json,lock}`
(intentionally dropped here per the Lix/devbox plan).

**Live, need a home in the flake**: `.claude/keybindings.json`,
`.claude/bin/{claude-mcp-sync,claude-zed-threads}`,
`.config/claude/mcp.json`, `.cargo/config.toml`, `.pip/pip.conf`,
`.config/kitty/themes/` (see decision above), `.local/share/spicetify`,
`.local/share/kitty/.gitkeep` (dir creation, trivially an activation mkdir).

**Deliberately elsewhere**: `Documents/Obsidian/Brain/.obsidian/themes/`
(Obsidian vault theming; Resilio/vault territory, not dotfiles).

## (f) `~/.claude` config inventory (declare in flake later; nothing wired yet)

Already castle-linked today (so the flake should own them at migration):
`settings.json`, `keybindings.json`, `CLAUDE.md`, `commands/resume-zed.md`,
`bin/claude-mcp-sync`, `bin/claude-zed-threads`.

Config-like but not castle-tracked yet, worth declaring:
- `rules/typescript.mdc`
- `skills/gh-stack/` (real directory) and `skills/find-skills` (symlink into
  `~/.agents/skills/`, which holds both; decide whether `~/.agents` is the
  canonical home and the flake links `~/.claude/skills` entries into it)
- `settings.local.json`: decide per-machine vs shared before declaring
- `.config/claude/mcp.json` (pairs with `claude-mcp-sync`)

State, never declare or sync: `.credentials.json`, `projects/`, `todos/`,
`sessions/`, `session-env/`, `shell-snapshots/`, `history.jsonl`, `daemon.*`,
`plugins/` caches (`installed_plugins.json` is arguably config; the rest is
cache), `stats-cache.json`, `file-history/`, `paste-cache/`, `backups/`,
`cache/`, `debug/`, `telemetry/`, `tasks/`, `jobs/`, `ide/`,
`remote-settings.json`, `policy-limits.json`, `mcp-needs-auth-cache.json`,
`gh-pr-status-cache.json`, `plans/` (session artifacts).

The projects/state sync question is deliberately out of scope here: it's the
claude-sync thread's problem. This inventory is only the *config* surface.
