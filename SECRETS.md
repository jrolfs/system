# Secrets & private configuration

Plan for getting off git-crypt-in-a-homeshick-castle, without losing the things
that setup does well. Independent of the flake migration — steps 1 and 2 can
happen at any time, on either side of it.

Companion docs: [MIGRATION.md](MIGRATION.md), [BACKPORT.md](BACKPORT.md).

## Why

The `private` castle uses git-crypt, which means:

- **No rotation.** If the key leaks, every historical commit is decryptable,
  forever, and the ciphertext is on GitHub.
- **Deterministic IV** (HMAC of plaintext) — identical files produce identical
  ciphertext, so equality leaks.
- **Metadata leaks** — filenames, sizes, and *which* files are encrypted.
- **Fail-open.** If `.gitattributes` doesn't match a path, or a file is
  committed before the rule exists, plaintext lands in history permanently.

That last one is the real risk, and it's why the current setup feels
error-prone.

## What's actually in there

Counted from `git ls-files`, and cross-referenced against the `-filter -diff`
opt-outs in `.gitattributes` (i.e. what is *deliberately not* encrypted):

**Project overlays — 36 paths, the bulk of the castle**
`Developer/Hover/*` (22), `Developer/Sources/*` (14). Mostly `devbox.json`,
`devbox.lock`, `process-compose.yml`, `.envrc`, editor settings. Already
excluded from git-crypt, i.e. already treated as non-secret.

**Encrypted, genuinely secret**
`.config/ngrok/ngrok.yml`, `.config/openaiapirc`, `.config/rclone/rclone.conf`,
`.config/zsh/init/keys.zsh`, `.kube/config`, `.npmrcs/{default,hover,hover-read-only}`,
`.travis/config.yml`, `.local/share/resilio/resilio-sync--license.btskey`,
`history` + `.local/share/history` (encrypted zsh history submodule).

**Not encrypted, not secret — just private**
`.config/git/authors.yml`, `.config/nvim/sessions/*`, `.ssh/config`,
`.ssh/known_hosts`, `.gnupg/sshcontrol`, `.wakeonlan/*`.

**Device-local — must not sync**
`.config/op/config` (per-device UUID; see BACKPORT.md item 1).

**Likely defunct** — Hover is a former employer (`ORGANIZATION` moved to
`meterup`): `Developer/Hover/*` (22 paths), `.npmrcs/hover*`,
`.local/share/hover/bin/infractl{,-update}`, and `.travis/config.yml` (Travis).

So: **the castle is mostly a private config-overlay store that happens to have
encryption switched on**, with a genuinely-secret set of roughly ten items —
several of which are dead.

## The bootstrap dependency chain

`.git-crypt/keys/default/0/91C155A78968EEE863ED8B22626AE770762AC2F3.gpg` is the
git-crypt symmetric key, encrypted to the GPG key. So on a fresh machine:

```
1Password  →  GPG secret key  →  git-crypt unlock  →  castle contents
```

The GPG key therefore **cannot** live in the castle — it's the thing that opens
it. That's why the `gpg-imported` bootstrap phase sources it from 1Password, and
it's a good argument for 1Password as the root of trust generally: it's the one
store that needs nothing else to already work.

The last step is the `castle-unlocked` phase, immediately after `gpg-imported`.
It was missing until now, and the failure mode is worse than "secrets aren't
available": every encrypted path is *ciphertext sitting where a real file
should be*, and `.config/zsh/init/keys.zsh` is one of them, so `.zshrc` snippets
binary into every shell. The phase is not recorded unless the unlock succeeds,
so a re-run retries it — useful, because `git-crypt unlock` refuses a dirty
working tree and needs a passphrase prompt to get through.

Two details that only bite inside bootstrap: `git-crypt` and `gpg` are resolved
by absolute path (the flake wrapper sets `PATH` to nix store bins only), and
gpg's directory is prepended to `PATH` for the call because git-crypt shells out
to `gpg` by name.

## Target design: three categories, three homes

| Category | Home | Mechanism |
|---|---|---|
| Secrets | 1Password | `op` + a committed manifest of `op://` refs; materialized to disk with `0600` where a tool needs a file |
| Private, not secret | a plain private repo (the castle, minus git-crypt) | symlinks — homeshick or `mkOutOfStoreSymlink`, same thing |
| Device-local | nowhere | never synced |

Splitting these is most of the value. Encryption is the wrong axis to organize
by; **"is it a credential"** is the right one.

## Anti-patterns to avoid

- **Secrets in the nix store.** `/nix/store` is world-readable. Anything
  interpolated at eval time is there permanently. Decrypt/fetch at *activation*
  or *runtime* into a path with restrictive modes.
- **Secrets in the ambient shell environment.** `export FOO=$(op read …)` in
  `.zshenv` costs an `op` round-trip (network, possibly biometric) on *every*
  shell spawn, and exposes the value to every child process. Prefer, in order:
  1. **`op plugin`** for supported tools — `op plugin init <tool>` makes the
     tool fetch its own credential, biometric-gated. Already in use for `gh`.
  2. **`op run -- <command>`** — scoped to one process.
  3. A **lazy shell function** that fetches on first use and caches for the
     session.

  `.config/zsh/init/keys.zsh` is the current instance of this anti-pattern and
  the main candidate for `op plugin` / `op run`.
- **Syncing `~/.gnupg` wholesale.** gpg-agent mutates `private-keys-v1.d`, and
  there are sockets and lock files in there. Export/import instead.

## `mkOutOfStoreSymlink` is homeshick

The worry about losing symlink immediacy — edit a file, no rebuild — is solved
without giving anything up:

- **Store symlink** (`home.file."x".source = ./x`) — immutable, atomic, needs a
  `darwin-rebuild switch` to change.
- **Out-of-store symlink** (`config.lib.file.mkOutOfStoreSymlink "…"`) — points
  at the **live working tree**. Edit, and it's in effect immediately. This is
  exactly what `hs link` produces.

Already used for `zed`, `karabiner`, and the vscode sync repo. Anything edited
frequently is a candidate. The choice is per-file, not global.

## Project overlays

`home.file` paths are `$HOME`-relative at arbitrary depth, so the castle's
`private/home/Developer/Sources/…` mapping ports directly:

```nix
home.file."Developer/Sources/meterup/frontends/.zed/settings.json".source =
  config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/…/overlays/…";
```

But these aren't secrets — the requirement is *privacy* (internal project names,
URLs), and this repo is public. Options: a private repo consumed as a flake
input, or **just keep a slimmed castle for them**. Not everything has to
migrate; a castle holding only non-secret overlays can drop git-crypt entirely
and become a plain private repo. That's simpler than today.

Per-repo gitignore overlays (`ignore-claude`, `ignore-zed`,
`ignore-devbox-and-claude-and-zed`, selected via `includeIf`) already live in the
git config and port as-is.

## Flakes and symlinks (orthogonal)

Nix excludes untracked files when a flake lives in a git repo, so a symlinked
`flake.nix` is invisible to the project's repo — hence the `ln-h` hardlink
alias. This is true under home-manager too; migrating neither helps nor hurts.

Cleaner escape: a `path:` flakeref bypasses git-tracking entirely.

```bash
nix develop 'path:.'
```

Also worth knowing: hardlinks silently break when an editor saves atomically
(write-temp-then-rename), which makes `ln-h` fragile for actively edited files.

## The `bootstrap secrets` CLI

Built — lives in the **bootstrap repo** (`src/secrets.ts`), which already had the
`op` plumbing, zod schemas, and phase logging, and is already cloned on every
machine.

It's a subcommand tree under the one `bootstrap` binary rather than its own
`secrets` binary: that keeps every generic name off `PATH`, most importantly
`gpg`, which as a top-level command would shadow the real one.

```
bootstrap secrets list              # manifest: name → op:// ref → target, host-marked
bootstrap secrets check             # every reference resolves
bootstrap secrets materialize [<name>…]
                                    # write entries with a target to disk (0600)
bootstrap secrets add <name> --reference op://… [--target --mode --hosts --kind --description]
bootstrap secrets gpg export [<keyring>]
                                    # capture a keyring → 1Password, record refs
bootstrap secrets gpg import        # import every keyring for this host
```

The manifest is `secrets.json` in the bootstrap repo. It records `op://`
references — **not secrets** — so it's committed and reviewable, and a lost
reference is a `git log` away rather than a hunt through the vault. That's what
makes `materialize` a single command, i.e. the `hs link private` equivalent.

Each entry carries `hosts`, so a secret can be gated to specific machines
(`["*"]` for all). `gnupgHome` routes GPG entries to the right keyring.

**Two ways to run it**, which is what resolves the migration chicken-and-egg:

```bash
nix run github:jrolfs/bootstrap#cli -- secrets list  # no checkout needed
nix develop -c bootstrap secrets gpg export          # from a clone; required for
                                                     # anything that writes the
                                                     # manifest (store copy is
                                                     # read-only)
```

Plus, once wired, on `PATH` via the system flake — see `modules/bootstrap.nix`:

```nix
inputs.bootstrap.url = "github:jrolfs/bootstrap";
# …
environment.systemPackages = [ inputs.bootstrap.packages.${system}.bootstrap ];
```

One implementation, used by bootstrap phases *and* interactively — the
`gpg-imported` phase calls the same module as `bootstrap secrets gpg import`.

### The dedicated vault

`onePassword.secretsVault` is where the CLI *creates* items, kept separate from
`vault` (used to expand short-form references) so a dedicated vault doesn't break
existing references pointing at the personal one.

Worth having beyond tidiness: **1Password service accounts grant access per
vault**, so a headless host can later be given a token scoped to just these
secrets rather than a ~1300-item personal vault. Create it with
`op vault create Secrets`.

### `op` CLI quirks worth not rediscovering

Both of these were found verifying the first real export, and both fail in ways
that look like something else.

**`op document get` does not accept `op://` references.** It wants a UUID, name,
or domain, and rejects a reference with `"op://…" isn't an item`. Only `op read`
parses that syntax, and only for *field* references. The manifest still stores
`op://Vault/Item` — opaque UUIDs would defeat the point of a reviewable file —
so `readDocument` splits it back into `<item> --vault <vault>`.

**`--account` must not be passed to `op whoami`.** Data commands take it fine,
and it's needed: without it `op` can fail with `multiple accounts found` on a
machine signed into a personal *and* a work account, and vault names aren't
unique across accounts. But `whoami` reports the session the **desktop app** is
providing, and the flag makes `op` look for an `op signin` session instead — so
it returns `account is not signed in` on a perfectly healthy machine. Since
`whoami` is the auth probe, passing it there makes bootstrap conclude `op` is
unauthenticated and throw after its guided retries.

### Multiple keyrings

`gpg.keyrings` in the bootstrap config lists keyrings, each with a name, an
optional `GNUPGHOME`, an optional fingerprint, and `hosts`.

This exists because **GnuPG does not partition secret keys by keyring**:
`--keyring` selects a public keybox, but secret keys all live in one flat
`private-keys-v1.d` per `GNUPGHOME`. So `gpg --keyring=fondo.kbx` cannot keep the
fondo secret key off a work machine — only a separate home can.

Configured today:

| Keyring | GNUPGHOME | Hosts | Notes |
|---|---|---|---|
| `default` | `~/.gnupg` | all | fingerprint `91C155A7…762AC2F3` |
| `fondo` | `~/.gnupg-fondo` | `newt`, `ala` | no fingerprint → exports every key in that home |

Access the secondary one with `GNUPGHOME=~/.gnupg-fondo gpg …` (an alias is
warranted). Don't put `keyring` in `gpg.conf` — that applies globally and
defeats the separation.

### What a complete keyring capture requires

Three distinct artifacts — this caught me out once, so it's worth being explicit.
`--export-secret-keys` embeds only each secret key's *own* public half, and
ownertrust is not key material at all:

| Command | Contents | Backing file |
|---|---|---|
| `gpg --armor --export` | **all** public keys — yours *and* other people's | `pubring.kbx` |
| `gpg --armor --export-secret-keys` | your secret keys | `private-keys-v1.d/` |
| `gpg --export-ownertrust` | trust *assignments*: fingerprint → level | `trustdb.gpg` |

Exporting only the last two silently drops every third-party public key, leaving
a provisioned machine unable to encrypt to anyone. `bootstrap secrets gpg export`
captures all three, per keyring, as
`<name>-{public-keys,secret-keys,ownertrust}`.

Import order is public → secret → ownertrust, since ownertrust references keys by
fingerprint. Public keys are re-imported on every run (idempotent) so a keyring
that gains correspondents converges rather than being skipped forever.

Not captured, deliberately: `gpg.conf` / `gpg-agent.conf` / `scdaemon.conf`
(config — they belong in `dotfiles/home/.gnupg/`, delivered by home-manager),
`sshcontrol` (keygrips, non-secret), and sockets / `random_seed` / lock files
(machine-local runtime state, never sync). `openpgp-revocs.d/` revocation
certificates are also not captured — worth a separate backup if you care about
them.

## Sequencing

1. **Prune.** `Developer/Hover/*` (22), `.npmrcs/hover*`, `hover/bin/infractl*`,
   `.travis/config.yml`. Independent, immediate, shrinks everything downstream.
2. **Split** — even if only on paper at first: mark each remaining path as
   secret / private-not-secret / device-local.
3. **GPG first** (priority). `bootstrap secrets gpg export` → 1Password documents
   → set `gpg.{secretKeyOpReference,ownertrustOpReference}` in the bootstrap
   config. Half of this exists already (see Status).
4. **Migrate the remaining secrets one at a time**, with `materialize` proving
   each before removing it from the castle.
5. **Then `op plugin`** for tools that support it — may eliminate several
   manifest entries outright, `keys.zsh` especially.
6. **Finally** decide whether the castle drops git-crypt and stays (overlays
   only), or goes away entirely.

## Status

**Written and typechecked, but not yet exercised against a real vault.** Only
`bootstrap help` has actually been run — the first `gpg export` is the real test.

- **Done:** the `bootstrap secrets` CLI (`list`, `check`, `materialize`, `add`,
  `gpg export`, `gpg import`), the zod-validated `secrets.json` manifest with
  per-entry `hosts` gating, and one `bootstrap` binary exposed as both a flake
  package (`modules/bootstrap.nix` puts it on `PATH`) and an app.
- **Done:** `gpg-imported` bootstrap phase, now iterating `gpg.keyrings` and
  skipping keyrings gated to other hosts. Key material is piped straight into
  `gpg --batch --import` on stdin — never a temp file, never in argv.
- **Done:** `castle-unlocked` phase (`git-crypt unlock`), and the castle pull +
  link moved out of the `private-cloned` phase gate so a re-run actually
  updates the castle instead of skipping it as cached.
- **Done:** `readDocument()` and `createDocument()` in `onepassword.ts`, both with
  re-auth-and-retry. `createDocument` writes via stdin and edits in place when the
  title exists, so references (and therefore manifest entries) stay stable across
  re-exports.
- **Done:** `onePassword.secretsVault`, and the dead `darwin` input removed from
  the bootstrap flake (it would have dragged an extra nix-darwin + nixpkgs into
  any consumer's closure).
- **Not started:** creating the `Secrets` vault, the first export, the
  `fondo` home migration (see below), wiring the CLI onto `PATH` via the system
  flake, migrating the remaining secrets, and the prune.

### Migrating `fondo` into its own GNUPGHOME

The config expects `~/.gnupg-fondo`, but the keys currently live in the default
home, reachable via `--keyring=fondo.kbx`. One-time move, per fondo key:

```bash
export FONDO=<fondo-key-fingerprint>

mkdir -p -m 700 ~/.gnupg-fondo

# Move: export from the default home, import into the new one.
gpg --armor --export-secret-keys "$FONDO" \
  | GNUPGHOME=~/.gnupg-fondo gpg --batch --import

# Verify it landed before removing anything.
GNUPGHOME=~/.gnupg-fondo gpg -K

# Only then remove from the default home (secret first, then public).
gpg --delete-secret-keys "$FONDO"
gpg --delete-keys "$FONDO"
```

Then `bootstrap secrets gpg export fondo` records it. Keep a backup of the
original `fondo.kbx` until the new home is verified — `--delete-secret-keys` is
not reversible.

