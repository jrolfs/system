# Moving Leia's services to Irulan

Irulan exists to take over what Leia (the QNAP NAS) runs today, so that Leia
is left doing what a NAS is good at: holding the media and running the
download stack that writes to it. This document is the plan for getting there:
which service goes where, in what order, what state moves with each, and how
each step is undone.

The companion repo is `jrolfs/rolfs.lan`, checked out at
`~/Developer/Sources/jrolfs/rolfs.lan`. Its `CLAUDE.md` describes Leia's stack
as it is, and its `kath/network.md` is the address plan.

## End state

| Host | Runs |
|---|---|
| Irulan | Traefik, step-ca, Home Assistant and the Matter server, Pi-hole, Plex, Uptime Kuma and dhcp-probe, Komodo Core |
| Leia | The download stack (qBittorrent, qui, NZBGet, Sonarr, Radarr, Prowlarr, Unpackerr, TubeSync), Resilio Sync, the QNAP admin UI, and a Komodo periphery |

The download stack stays because every piece of it writes into
`/share/Media`, and its imports are hardlinks and renames that only work on the
one filesystem (rolfs.lan's `CLAUDE.md`, "Download Stack"). Over NFS they would
become copies.

## How the hosts fit together

Most of this plan is moving one service at a time. The parts that make that
possible, and that stay true after every phase, are below.

### Where each piece of configuration lives

| What | Where | Applied by |
|---|---|---|
| Irulan's OS, and services run as NixOS modules | this repo, `hosts/irulan/` and `modules/nixos/services/` | `nix-switch` on Irulan |
| Komodo stacks, on any host | rolfs.lan, `<host>/<stack>/compose.yaml` | Komodo, through that host's periphery |
| Traefik routes | rolfs.lan, wherever Traefik runs (today `leia/docker/traefik/config/servers.yml`) | Traefik's file provider, live on pull |
| DNS names, DHCP reservations, NAT | pfSense on kath, by hand; recorded in `kath/network.md` | nothing; kath is not deployed from a repo |

A service is a NixOS module when it has a good one and doesn't need a LAN
address of its own (Plex, the Komodo periphery). It is a Komodo stack when it
is already a well-understood container, needs its own LAN IP and MAC, or would
need its whole integration surface translated into Nix to run natively (Home
Assistant, Pi-hole, Traefik).

### Komodo with more than one server

One Core, on Leia until the last phase. Every host Komodo deploys to runs a
periphery, and each is a Komodo **Server named after its short hostname**:
Leia's already connects as `leia`, and Irulan's connects as `irulan`.

- **Both peripheries dial out.** Leia's connects to `ws://core:9120` on its
  own Compose network. Irulan's is `services.komodo-periphery` (the nixpkgs
  module, through `komodo.periphery.enable` in
  `modules/nixos/services/komodo.nix`), connecting to
  `https://komodo.rolfs.casa` through Traefik. Neither host listens for Core,
  so Irulan's firewall opens nothing for it.
- **Keys are generated, not distributed.** A periphery creates its key pair on
  first start (`/var/lib/komodo-periphery/keys` on Irulan) and Core stores the
  public half of an unknown connection as the server's *attempted* public key
  until it is accepted in the UI. No onboarding key and no 1Password item is
  needed for a new host.
- **Stacks are named `<host>-<stack>`** and their run directory in rolfs.lan
  starts with the host directory (`irulan/monitoring/`). A stack's server
  assignment then matches where its files sit. Leia's single stack, Compose
  project `rolfs-casa` at `leia/docker/`, shrinks as services leave it.
- **Each periphery keeps its own clone.** Leia's is under
  `/share/Docker/Containers/komodo/data/repos`, Irulan's under
  `/var/lib/komodo-periphery/repos`. Anything gitignored, like Leia's
  `*.secrets.env` files, exists only in the clone it was put into, so it does
  not follow a stack from one host to the other.

### Reaching a service on another host

- **Traefik's Docker provider sees only its own host.** Labels on an Irulan
  container do nothing for Traefik on Leia. Anything on Irulan is routed from
  `servers.yml` by `irulan.rolfs.lan:<port>`, which is how `plex-irulan` works
  in phase 1. Once Traefik moves, the same is true in reverse: Leia's
  label-routed services need published ports and file-provider entries.
- **Compose service names don't cross hosts.** A container on Irulan cannot
  resolve `sonarr` or `step-ca`. Cross-host references go through
  `<host>.rolfs.lan:<published port>`, or through Traefik by service name.
- **A macvlan container can't reach its own host, nor the host it.** That is
  QNAP's qnet bridge today (the reason dhcp-probe is dual-homed), and the same
  holds for a macvlan network on Irulan. When Traefik and Home Assistant are
  both on Irulan, Traefik needs either a leg on the macvlan network or a
  macvlan shim interface on the host (`networking.macvlans`).

### Names and addresses

- **Irulan gets a static mapping.** It is on a dynamic lease today, which
  registers `irulan.rolfs.lan` but can move. Phase 1 recommends `10.10.10.14`,
  the first free address after newt.
- **`*.rolfs.casa` is one unbound redirect zone**, `local-zone: "rolfs.casa."
  redirect` with the apex pointing at `10.10.10.12`, in kath's DNS Resolver
  custom options. Every `.casa` name follows it, so a new `.casa` route needs
  no DNS change.
- **`rolfs.lan` names are host-override aliases**, all on the `leia` override
  because Traefik is there. A new `-lan` route needs its alias added, on
  whichever host runs Traefik (not on the host running the backend).
- **Meter's subnet reaches Leia through two NAT rules** on OPT1: 443 for
  `rolfs.casa` and 32400 for Plex. Both are retargeted when what they point at
  moves.

### Secrets

Phase 1 needs none. Each later phase lists what its service carries, and the
plumbing is decided when the first stack holding a secret moves. Two
constraints shape that choice:

- Leia's pattern, gitignored `*.secrets.env` files placed by hand in Komodo's
  clone, doesn't move with a stack (see above).
- An `env_file` secret is written unredacted into Komodo's Update logs since
  2.3.0, as `docker compose config` output
  ([komodo#1636](https://github.com/moghtech/komodo/issues/1636), open).

For native services, `onepassword.templates` (`modules/nixos/onepassword-secrets.nix`)
is already the answer. For stacks, the candidates are Komodo's own secret
interpolation (`[[NAME]]`) and files rendered on the host by the same
`onepassword.templates`, read from a fixed path rather than the clone.

## Inventory

| Service | Today | Destination | Phase | State to move |
|---|---|---|---|---|
| Plex | QPKG on Leia | Irulan, NixOS module | 1 (parallel), 3 (cutover) | the QPKG's `Library/Plex Media Server`, if the library moves (phase 3) |
| Komodo periphery | container on Leia | stays on Leia; a second one on Irulan, native | 1 | none |
| Uptime Kuma | Leia stack | Irulan, stack `irulan-monitoring` | 2 | `/share/Docker/Containers/uptime-kuma/data` |
| dhcp-probe | Leia stack, macvlan `.99` | Irulan, stack `irulan-monitoring` | 2 | none; MAC `02:42:0a:0a:0a:63` is pinned to its Kea reservation |
| Home Assistant | Leia stack, macvlan `.2` | Irulan, stack `irulan-home` | 4 | `/share/Docker/Containers/home-assistant/config` |
| Matter server | Leia stack, host network | Irulan, stack `irulan-home` | 4 | `/share/Docker/Containers/matter/data` (the fabric credentials) |
| Pi-hole | Leia stack, macvlan `.1` | Irulan, stack `irulan-dns` | 5 | `/share/Docker/Containers/pihole/config`; MAC `02:42:a0:a0:e4:fd` |
| Traefik | Leia stack | Irulan, stack `irulan-edge` | 6 | `traefik-acme` volume (`letsencrypt.json`, `step.json`) |
| step-ca | Leia stack | Irulan, stack `irulan-edge` | 6 | `step-ca-data` volume, which is the CA itself |
| Komodo Core and Mongo | Leia, own Compose project | Irulan, `komodo.core.enable` | 7 | Mongo database, `/config/keys` (Core's key pair) |
| Download stack | Leia stack | stays | n/a | n/a |
| TubeSync | Leia stack | stays | n/a | writes `/share/Media/YouTube`, so it belongs with the downloaders |
| Resilio Sync | QNAP app | stays | n/a | it syncs the storage it sits on |
| QNAP admin UI | QNAP | stays | n/a | routed as `nas` and `leia` |
| Portainer | Container Station, standalone | stays while Leia runs containers; retire once Komodo has covered both hosts for a while | n/a | none |
| Homebridge | directory in rolfs.lan, not in the Compose file | **decide**: retire, or a stack on Irulan with host networking for HAP | n/a | `leia/docker/homebridge` |
| vdirsyncer | env file in rolfs.lan, not in the Compose file | **decide**: retire, or a stack or timer on Irulan | n/a | unknown |

`home-assistant.nix` and `step-ca.nix` in `modules/nixos/services/` were
written for a native move. This plan recommends containers for both instead
(phases 4 and 6 say why), so treat those modules as the alternative rather
than the plan of record. `home-assistant.nix` was imported on Irulan from
its first scaffold, running a Home Assistant nobody had set up, with its
onboarding page open on the LAN; it no longer is.

## Phases

Each phase ends with the service running on Irulan and its Leia copy stopped
but not deleted, so rollback is starting it again. Deleting the Leia copy and
its data is a separate cleanup, after a soak period of a couple of weeks.

### Phase 1: Irulan joins Komodo, and a parallel Plex

Done in branch `irulan-komodo-plex` here and `irulan` in rolfs.lan. Nothing on
Leia is stopped.

Why first: it changes nothing anyone uses. It proves the periphery path,
the cross-host Traefik route, the NFS mount and Quick Sync, each of which
later phases depend on.

What changed:

- `komodo.nix` is split into `komodo.core.enable` and
  `komodo.periphery.enable`, and Irulan enables only the periphery.
- Plex runs natively on Irulan as a fresh server, reading `/mnt/nas/media`
  read-only over NFS, with its database on the SSD.
- `plex-irulan.rolfs.casa` and `plex-irulan.rolfs.lan` route to
  `irulan.rolfs.lan:32400` from Leia's Traefik.

Steps outside either repo, in order:

1. **pfSense: a static mapping for Irulan.** Services → DHCP Server → LAN,
   add a mapping for Irulan's MAC (`ip link` on Irulan) at `10.10.10.14`,
   hostname `irulan`. Renew the lease (or reboot Irulan) and record it in
   `kath/network.md`.
2. **pfSense: the `.lan` alias.** Services → DNS Resolver → Host Overrides →
   `leia`, add the alias `plex-irulan`. It goes on `leia` because the name has
   to reach Traefik.
3. **QNAP: allow Irulan on the NFS export.** Control Panel → Shared Folders →
   Media → Edit Shared Folder Permission → NFS host access: allow
   `10.10.10.14`, read-only. Then check the export path with `cat /etc/exports`
   on Leia and correct `fileSystems."/mnt/nas/media".device` in
   `hosts/irulan/default.nix` if it isn't `/Media`. From Irulan,
   `ls /mnt/nas/media` triggers the automount.
4. **Switch Irulan** to this branch.
5. **Komodo: add the server.** In Komodo, Servers → New Server, name `irulan`,
   with no address (an empty address means Core waits for the periphery to
   connect). Within a few seconds the periphery connects and is refused, and
   the server shows the attempted public key. Accept it. If the server shows
   nothing, `journalctl -u komodo-periphery` on Irulan shows whether it reached
   `komodo.rolfs.casa` at all.
6. **Deploy rolfs.lan's `irulan` branch on Leia**, or merge it. Traefik picks
   up `servers.yml` on pull, with no restart.
7. **Claim the new Plex.** The native module has no claim-token option (that
   is a Docker image feature), so the server is claimed by signing in to its
   own web UI, and Plex is strict about where an unclaimed server accepts that
   from. Going through Traefik doesn't work, since requests arrive from Leia.
   The dependable route is a tunnel: `ssh -L 32400:localhost:32400 irulan`,
   then open `http://localhost:32400/web` and sign in. A browser on Irulan's
   own desktop works too. Name it something other than
   Leia's server (for example `Irulan`).
8. **Plex settings.** Settings → Transcoder → "Use hardware acceleration when
   available" (needs Plex Pass). Settings → Library → turn off "Empty trash
   automatically after every scan", so a scan while the NAS is unreachable
   can't drop the library. Add libraries from `/mnt/nas/media/TV` and
   `/mnt/nas/media/Movies`.
9. **Check Quick Sync**: play something that forces a transcode, and the
   dashboard shows `(hw)` beside the stream.

Rollback: `komodo.periphery.enable = false` and drop `plex.nix` from
Irulan's imports, revert the `servers.yml` commit, delete the `irulan` server
in Komodo. Leia is untouched throughout.

### Phase 2: monitoring

Uptime Kuma and dhcp-probe, as the stack `irulan-monitoring` at
`irulan/monitoring/compose.yaml`.

Why second: it is the first real Komodo stack on Irulan, so it is where the
repo layout, server assignment and cross-host routing get exercised, and
very little depends on it. Monitoring also belongs off the NAS: Kuma on Leia
cannot report Leia being down.

- **State**: copy Kuma's data directory with Kuma stopped. It is SQLite.
- **Changes**: Kuma's Docker-container monitors read Leia's socket and can't
  from Irulan. Replace them with HTTP or TCP monitors. dhcp-probe pushes to
  Kuma by stack name today, so its push URL becomes Kuma's Traefik name.
  dhcp-probe needs a macvlan network on Irulan, with the pinned MAC, for its
  DHCP exchange to reach kath.
- **Secrets**: `dhcp-probe.secrets.env`. Kuma's notification credentials are
  in its database and move with it.
- **DNS/Traefik**: `status.rolfs.*` moves from Docker labels to a
  `servers.yml` entry pointing at Irulan.
- **Rollback**: stop the stack, start Kuma and dhcp-probe on Leia again.

### Phase 3: Plex cutover

Decide first between keeping the fresh server from phase 1 and moving the
QPKG's library. Moving the library keeps watch state, collections, and the
server's identity (so clients and shared users follow without being re-invited).
Keeping the fresh server is simpler, but loses all of that.

If the library moves:

- Mount the NFS share at `/share/Media` as well (or instead), so the
  QPKG's library paths resolve on Irulan unchanged. Otherwise every library
  path in the database needs rewriting.
- Stop the QPKG. Copy its `Library/Plex Media Server` directory
  (under `/share/MD0_DATA/.qpkg/PlexMediaServer`) over `/var/lib/plex`'s,
  replacing the phase-1 server. Never run both afterwards: they would share
  one identity.
- Point the `plex` service in `servers.yml` at Irulan, and drop `plex-irulan`.
  Retarget the Meter NAT rule for 32400 to `10.10.10.14`.
- Rollback: stop Plex on Irulan, start the QPKG, revert `servers.yml` and the
  NAT rule. The QPKG's copy is the state as of the cutover.

### Phase 4: Home Assistant and the Matter server

The stack `irulan-home`, with Home Assistant on a macvlan network at
`10.10.10.2` and the Matter server on host networking.

Recommended as containers, not `home-assistant.nix`: the container keeps
HACS's `custom_components` and the UI-managed YAML working as they are, and
keeps HA's address, which device integrations and HomeKit pairings hold on to.
The native module would need every integration's Python dependencies declared
in Nix first.

- **Order**: the two move together, since HA talks to the Matter server and
  the Matter fabric credentials live in its `/data`.
- **State**: both data directories, copied with both containers stopped.
  HA's `secrets.yaml` is in its config directory and moves with it. The
  repo-tracked config mounts (rolfs.lan's `CLAUDE.md`, "Home Assistant's
  config mounts") repeat under `irulan/home/`.
- **Rollback**: stop on Irulan, start on Leia. Leia's copy is as of the
  cutover, so changes made on Irulan in between are lost unless copied back.

### Phase 5: Pi-hole

The stack `irulan-dns`, on a macvlan network at `10.10.10.1` with the MAC
from its Kea reservation.

- **Cutover**: stop Leia's, then start Irulan's. The same IP and MAC can't be
  up twice. During the gap clients fall back to kath (`10.10.10.10`), which
  DHCP hands out as the second server.
- **State**: Pi-hole's config directory.
- **Secrets**: `pihole.secrets.env` (the web password).
- **Rollback**: the reverse.

### Phase 6: Traefik and step-ca

The careful one: Traefik fronts every name, so a mistake here takes everything
down at once. Do it as a parallel Traefik first and move names to it
gradually.

1. **Stand up `irulan-edge`** with Traefik alone, routing only through the
   file provider. Copy `letsencrypt.json` from the `traefik-acme` volume first,
   so it doesn't request a fresh certificate for every name (Let's Encrypt
   limits identical certificates to 5 a week). DNS-01 through Vercel works
   from either host, so both Traefiks can renew.
2. **Make the file provider a directory** (one file per backend host, such as
   `leia.yml` and `irulan.yml`) rather than one `servers.yml`. Don't do this on
   Leia's running Traefik: the file provider setting is static configuration,
   applied only at restart, while the file move lands on the next pull. Leia's
   Traefik would lose every file route until it restarted.
3. **Publish ports for Leia's label-routed services** (Sonarr, Radarr, NZBGet,
   Prowlarr, qBittorrent, qui, TubeSync, Unpackerr's UI), and give each a
   file-provider entry on Irulan's Traefik.
4. **Move `.casa` names one at a time.** A more specific redirect zone wins
   over `rolfs.casa.`, so a single name can point at Irulan with
   `local-zone: "<name>.rolfs.casa." redirect` plus its `local-data` A record.
   Verify each name before the next.
5. **Move step-ca and the `.lan` names together.** Stop Leia's step-ca, copy
   the `step-ca-data` volume into `irulan-edge`, start it there, and move the
   service aliases from the `leia` host override to an `irulan` one. Leia's
   host name stays on `leia`: it is what NFS, SSH and the file provider use.
   The QNAP UI stays reachable as `nas.rolfs.*`.
6. **Flip the apex** of the `rolfs.casa.` zone to `10.10.10.14`, retarget the
   Meter NAT rule for 443, and remove the per-name zones.

- **Port 443 on Irulan**: `step-ca.nix` binds it. Run step-ca in the stack
  beside Traefik (where `https://step-ca:9000` keeps resolving and its
  certificate already names it), and retire that module.
- **Secrets**: `traefik.secrets.env` (the Vercel token). step-ca's password
  lives in its data volume.
- **Rollback**: at steps 4 and 5, delete the override or move the aliases
  back. At step 6, point the apex and the NAT rule at `10.10.10.12` again.
  Leia's Traefik keeps running until the soak ends.

### Phase 7: Komodo Core

Last, because it is the thing that deploys everything else, and nothing
depends on where it runs as long as `komodo.rolfs.casa` resolves to it.

- **State**: a `mongodump` from Leia restored into Irulan's Mongo, and Core's
  key pair from `/config/keys`. Leia's periphery pins Core's public key
  (`PERIPHERY_CORE_PUBLIC_KEYS`), so a new key pair would lock it out.
- **Leia's periphery** changes its core address from `ws://core:9120` to
  `https://komodo.rolfs.casa`, since Core is no longer beside it.
- **Secrets**: `komodo.secrets.env`. Render Core's and Mongo's environment
  through `onepassword.templates` here, which the TODO in `komodo.nix` marks.
- **Rollback**: start Core on Leia again. Its database is as of the cutover.
- Afterwards, `/share/Docker/Containers/rolfs.lan` on Leia (the old checkout
  Komodo deploys itself from) can finally go.

## Open questions

- Homebridge and vdirsyncer have files in rolfs.lan but no Compose entry. Are
  they running anywhere, and do they move or retire?
- Phase 3: move the QPKG's library, or keep the fresh server?
- Should Irulan's periphery pin Core's public key, as Leia's does? It would be
  `services.komodo-periphery.auth.corePublicKeys`, with the key from Core's
  `/config/keys/core.pub`. Not secret, but not in either repo yet.
