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
| Traefik routes | rolfs.lan: `leia/docker/traefik/config/servers.yml` for Leia's Traefik, `irulan/edge/traefik/dynamic/` for Irulan's | Traefik's file provider, live on pull |
| DNS names, DHCP reservations, NAT | pfSense on kath, by hand; recorded in `kath/network.md` | nothing; kath is not deployed from a repo |

A service is a NixOS module when it has a good one and doesn't need a LAN
address of its own (Plex, the Komodo periphery). It is a Komodo stack when it
is already a well-understood container, needs its own LAN IP and MAC, or would
need its whole integration surface translated into Nix to run natively (Home
Assistant, Pi-hole, Traefik).

### Komodo with more than one server

One Core, on Irulan, moved there ahead of the services
([KOMODO-CORE-CUTOVER.md](KOMODO-CORE-CUTOVER.md)). Every host Komodo deploys
to runs a periphery, and each is a Komodo **Server named after its short
hostname**: Leia's connects as `leia`, and Irulan's as `irulan`.

- **Both peripheries dial out, straight to Core.** Irulan's is
  `services.komodo-periphery` (the nixpkgs module, through
  `komodo.periphery.enable` in `modules/nixos/services/komodo`), connecting
  to the Core beside it at `ws://127.0.0.1:9120`. Leia's connects to
  `ws://irulan.rolfs.lan:9120`. Neither goes through Traefik, so either host
  stays manageable while Traefik is down. Irulan opens 9120 for Leia's
  periphery and for Traefik, which proxies the UI as `komodo.rolfs.casa`.
  Until the cutover, Core is on Leia and Irulan's periphery reaches it through
  `https://komodo.rolfs.casa`.
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
  in phase 1. Irulan's own Traefik (phase 6) is the same in reverse: Leia's
  label-routed services need published ports and file-provider entries there.
- **Compose service names don't cross hosts.** A container on Irulan cannot
  resolve `sonarr` or `step-ca`. Cross-host references go through
  `<host>.rolfs.lan:<published port>`, or through Traefik by service name.
- **A macvlan container can't reach its own host, nor the host it.** That is
  QNAP's qnet bridge today (the reason dhcp-probe is dual-homed), and the same
  holds for a macvlan network on Irulan. Home Assistant and the Matter server
  avoid it by running natively on the host network (phase 4). Pi-hole and
  dhcp-probe don't: anything on Irulan's host network that has to reach them,
  Traefik included, needs either a leg on the macvlan network or a macvlan
  shim interface on the host (`networking.macvlans`).

### Names and addresses

- **Irulan is `10.10.10.9`**, a static mapping in Kea.
- **`*.rolfs.casa` is one unbound redirect zone**, `local-zone: "rolfs.casa."
  redirect` with the apex pointing at `10.10.10.9` since 2026-11-02 (Leia's
  `10.10.10.12` before), in kath's DNS Resolver custom options. Every `.casa`
  name follows it, so a new `.casa` route needs no DNS change. `rolfs.dev.`
  and `rolfs.home.` are two more zones of the same shape, also pointing at
  `10.10.10.9` (phase 6).
- **`rolfs.lan` service names are `local-data` lines** in the same custom
  options, one per name, all pointing at Irulan's Traefik since 2026-11-04.
  They replaced the aliases on kath's `leia` host override. `rolfs.lan` can't
  be a redirect zone, because it also names every host, so a new `-lan` route
  needs its line added before its router exists.
- **Meter's subnet reaches `rolfs.casa` and Plex through two NAT rules** on
  OPT1, `198.51.100.1:443` and `:32400`, both still pointing at Leia. Both are
  retargeted to Irulan when Meter's routing is picked up again; the 443 one is
  what keeps Leia's Traefik running.

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
is the answer. **For stacks, it is Komodo secret variables**, decided with
phase 2's dhcp-probe, the first stack with a secret:

- 1Password is the source of truth. Each stack secret is an item in the
  **Secrets** vault, and `komodo.secrets` in `hosts/irulan/default.nix` maps a
  Komodo variable name to its `op://` reference. `komodo-secrets-sync`
  (`modules/nixos/services/komodo/`) reads each one with Irulan's service
  account and creates or updates the matching Komodo variable, with
  `is_secret` set, through Core's API. It runs at boot, on any switch that
  changes the declared set, and daily from `komodo-secrets-sync-refresh.timer`.
  Every value is read before anything is written, so if 1Password or Core is
  unreachable the unit fails and Komodo keeps what it had; a variable is never
  blanked. The journal shows names and created, updated or unchanged, never
  values. Komodo's copy is managed: an edit made in Komodo's UI is overwritten
  by the next sync. Undeclared secret variables are left alone and listed.
- The stack's **Environment** setting in Komodo passes it on, as
  `NAME=[[NAME]]`; the compose file reads `${NAME}`. Komodo interpolates
  `[[...]]` only in that setting (and in UI-defined compose contents), never
  in compose files cloned from git: there the placeholder arrives literally.
- Komodo knows the value is secret, so its Update logs show `<NAME>` where
  `docker compose config` would print it, unlike an `env_file`. Checked after
  phase 2's deploy: the log holds no token.

Adding a secret for a stack:

1. Create an item in the **Secrets** vault (Irulan's service account can't
   read Private).
2. Add one line to `komodo.secrets`, such as
   `DHCP_PROBE_PUSH_URL = "op://Secrets/dhcp-probe/push url";`, and switch
   Irulan. `journalctl -u komodo-secrets-sync` shows it created.
3. Add `NAME=[[NAME]]` to the stack's Environment in Komodo and `${NAME}` to
   its compose file, then deploy the stack.

Rotating one: change it at its source (a new Kuma push token, a new database
password), save the new value in 1Password, then either switch Irulan or wait
for the daily refresh, and redeploy the stack. The redeploy is what hands the
new value to the container. 1Password itself doesn't rotate anything; it only
holds the value and flags old ones in Watchtower.

## Inventory

| Service | Today | Destination | Phase | State to move |
|---|---|---|---|---|
| Plex | QPKG on Leia (stopped, disabled) | Irulan, NixOS module, with Leia's library | 3 (done) | moved: the QPKG's `Library/Plex Media Server` |
| Komodo periphery | container on Leia | stays on Leia; a second one on Irulan, native | 1 | none |
| Uptime Kuma | Leia stack | Irulan, stack `irulan-monitoring` | 2 | `/share/Docker/Containers/uptime-kuma/data` |
| dhcp-probe | Leia stack, macvlan `.99` | Irulan, stack `irulan-monitoring` | 2 | none; MAC `02:42:0a:0a:0a:63` is pinned to its Kea reservation |
| Home Assistant | Leia stack, macvlan `.2` | Irulan, native (`modules/nixos/services/home-assistant/`), keeping `.2` as a second address | 4 | `/share/Docker/Containers/home-assistant/config` |
| Matter server | Leia stack, host network | Irulan, native (`services.matter-server`) | 4 | `/share/Docker/Containers/matter/data` (the fabric credentials) |
| Pi-hole | Leia stack, macvlan `.1` | Irulan, stack `irulan-dns` | 5 | `/share/Docker/Containers/pihole/config`; MAC `02:42:a0:a0:e4:fd` |
| Traefik | Leia stack (retired 2026-11-04, behind the `retired-edge` profile) | Irulan, stack `irulan-edge`, serving all four domains | 6 (done) | none, since Irulan's requests its own certificates |
| step-ca | Leia stack (retired with Traefik) | a copy on Irulan, stack `irulan-edge` | 6 (done) | copied: the `step-ca-data` volume, which is the CA itself |
| Komodo Core and Mongo | Leia, own Compose project | Irulan, `komodo.core.enable` | 7, ahead of the others | Mongo database, `/config/keys` (Core's key pair) |
| Download stack | Leia stack | stays | n/a | n/a |
| TubeSync | Leia stack | stays | n/a | writes `/share/Media/YouTube`, so it belongs with the downloaders |
| Resilio Sync | QNAP app | stays | n/a | it syncs the storage it sits on |
| QNAP admin UI | QNAP | stays | n/a | routed as `nas` and `leia` |

### ↯ These have all been removed

| Portainer | Container Station, standalone | stays while Leia runs containers; retire once Komodo has covered both hosts for a while | n/a | none |
| Homebridge | directory in rolfs.lan, not in the Compose file | **decide**: retire, or a stack on Irulan with host networking for HAP | n/a | `leia/docker/homebridge` |
| vdirsyncer | env file in rolfs.lan, not in the Compose file | **decide**: retire, or a stack or timer on Irulan | n/a | unknown |

`step-ca.nix` in `modules/nixos/services/` was written for a native move.
Phase 6 runs step-ca as a container in `irulan-edge` instead, so the module is
imported nowhere (its line in `hosts/irulan/default.nix` is commented out) and
can be deleted.
`modules/nixos/services/home-assistant/` is the plan of record for phase 4,
imported on Irulan but off until then. From Irulan's first scaffold until
October 2026 it ran a Home Assistant nobody had set up, with its onboarding
page open on the LAN.

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
   add a mapping for Irulan's MAC (`ip link` on Irulan) at `10.10.10.9`,
   hostname `irulan`. Renew the lease (or reboot Irulan) and record it in
   `kath/network.md`.
2. **pfSense: the `.lan` alias.** Services → DNS Resolver → Host Overrides →
   `leia`, add the alias `plex-irulan`. It goes on `leia` because the name has
   to reach Traefik.
3. **QNAP: allow Irulan on the NFS export.** Control Panel → Shared Folders →
   Media → Edit Shared Folder Permission → NFS host access: allow
   `10.10.10.9`, read-only. Then check the export path with `cat /etc/exports`
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

### Phase 2: monitoring (done 2026-11-01)

Uptime Kuma and dhcp-probe run as the Komodo stack `irulan-monitoring` on
server `irulan`, from rolfs.lan's `irulan/monitoring/compose.yaml` on `main`.
Monitoring was down about six minutes (00:52 to 00:58).

What changed:

- **Kuma's data** is at `/srv/monitoring/uptime-kuma` on Irulan, outside the
  periphery's clone (created by `hosts/irulan`), copied with Kuma stopped.
  Its port 3001 is published, and Leia's Traefik routes `status.rolfs.*` to
  `irulan.rolfs.lan:3001` from `servers.yml`. Docker-published ports bypass
  NixOS's input firewall, so no firewall rule was needed.
- **dhcp-probe** keeps its pinned MAC `02:42:0a:0a:0a:63` and `10.10.10.99`
  reservation on a macvlan network on `enp3s0` (gateway kath), and pushes to
  Kuma by name over the stack's bridge. Its push URL is the first stack secret
  (see "Secrets").
- **Kuma's monitors** needed one change: none used Leia's Docker socket, but
  Matter's pointed at `leia.rolfs.lan:5580`. It now checks `irulan-host:5580`,
  Irulan itself through `host-gateway`. The Matter server's port is open only
  to the stack's bridge, which the compose file names `br-monitoring`
  (`networking.firewall.interfaces.br-monitoring` in `hosts/irulan`), since
  its API is unauthenticated.
- **Leia**: both services left `leia/docker/docker-compose.yml`, and their
  containers are stopped with `restart=no`, data kept, as the rollback.
- **The repo resource's webhook doesn't fire.** GitHub can't reach
  `komodo.rolfs.casa`, which only answers on the LAN, so a push to rolfs.lan
  reaches Leia's clone (and Traefik's routes) only on a Pull of the
  `rolfs.lan` repo in Komodo. Every routing change in later phases needs one.

Rollback: stop the stack, revert the `servers.yml` route, pull the repo, and
start Leia's `uptime-kuma` and `dhcp-probe` with `restart=always` (stop the
Irulan stack first: dhcp-probe's MAC and address can't be up twice).

### Phase 3: Plex cutover

**Done** on 2026-11-01, moving Leia's library rather than keeping the fresh
server from phase 1, which was never claimed and was set aside. About 13
minutes without Plex (02:25 to 02:38).

What moved, and how:

- **Server identity and state.** The QPKG's `Library/Plex Media Server`
  (8.6 GB, 35,501 files) was streamed over SSH from Leia straight into
  `/var/lib/plex`, with Plex stopped on both sides so the database's WAL was
  already checkpointed. Left behind as regenerable or QNAP-specific: `Cache`,
  `Codecs`, `Drivers`, `Logs`, `Crash Reports`, `Updates`. The server keeps
  its machine identifier (`decc6b1d…`) and its claim, so the six shared users
  and every client follow without re-inviting or re-pairing. Checks after the
  start: file counts identical, `PRAGMA quick_check` ok (23,979 metadata
  items, 2,903 with watch state), every section's item count equal to Leia's,
  and Plex.tv advertising Irulan's addresses.
- **Version.** Leia ran 1.43.5.11079 and the database only migrates forward,
  while nixpkgs (master included) was still on 11029. `plex.nix` overrides the
  package to 11079 only while nixpkgs is older, so it lapses after an update.
- **Paths.** The library recorded media under both `/share/Media` and
  `/share/MD0_DATA/Media`. Irulan mounts the export at both (and at
  `/mnt/nas/media`), so no path in the database was rewritten.
- **Settings changed:** `autoEmptyTrash="0"` was added to `Preferences.xml`
  before the first start, so a scan while the NAS is unreachable can't drop
  items. Hardware acceleration was already on.
- **Traefik:** the `plex` service in `servers.yml` points at
  `irulan.rolfs.lan:32400`. There was no `plex-irulan` route to drop: the
  phase-1 branch adding it was never merged.

Left for Jamie: the Meter NAT rule for 32400 on OPT1 still points at Leia.
It's on hold while Jamie reworks routing to the Meter subnet, and should point
at `10.10.10.9` as part of that. Also check Settings → Remote Access in Plex
reports the server as reachable.

kath's DNS Resolver now exempts `plex.direct` from rebinding protection
(`private-domain: "plex.direct"` in its custom options). Without it, local
clients couldn't resolve Plex's secure local addresses and went through
`plex.rolfs.casa` and Traefik instead, which Plex counts as a remote
connection because of the `X-Forwarded-For` header.

Rollback: `systemctl stop plex` on Irulan, then on Leia `qpkg_service enable
PlexMediaServer && qpkg_service start PlexMediaServer`, and point the `plex`
service in `servers.yml` back at `leia.rolfs.lan:32400`. Leia's copy is as of
the cutover. Never run both: they share one identity. After the soak, delete
the QPKG and `/var/lib/plex/Plex Media Server.unclaimed-spare` on Irulan.

### Phase 4: Home Assistant and the Matter server

Both native NixOS services, not a Komodo stack, in
`modules/nixos/services/home-assistant/` behind `homeAssistant.enable`:
Home Assistant through nixpkgs' `services.home-assistant`, and the Matter
server through `services.matter-server` (Python Matter Server, the same
software Leia's `ghcr.io/matter-js/python-matter-server` image runs). Jamie
wants Home Assistant configured in Nix, and both want the host network: Matter
needs IPv6 and multicast discovery on the LAN, and on the host network the two
reach each other on localhost, with no macvlan between them.

Imported on Irulan but off. Branch `home-assistant-native`.

#### What Leia runs (read 2026-10-31)

| | Leia | Irulan (pinned nixpkgs) |
|---|---|---|
| Home Assistant | 2026.10.4 (`homeassistant/home-assistant:latest`) | 2026.10.4 |
| Python Matter Server | 8.1.2 (`:stable`) | 8.1.2 |
| Config directory | 574 MB, of which the recorder database is 90 MB | |
| Matter data | 1.9 MB | |

Both match exactly. Re-check before the cutover: both of Leia's tags float,
and Home Assistant's `.storage` and database, like the Matter server's
storage, only migrate forward. Irulan's must never be older.

Integrations, from 59 config entries in `.storage/core.config_entries` plus
the YAML:

| Kind | Integrations | How Irulan gets them |
|---|---|---|
| Config entries | analytics, apple_tv (7), backblaze_b2, backup, broadlink, dlna_dmr, go2rtc, google_translate, group, homekit (14), hue, lifx, lutron_caseta, matter, met, mobile_app (5), radio_browser, shelly, shopping_list, sun, switchbot_cloud, thread, tplink (2), upnp, wake_on_lan, wemo, yoto | `extraComponents` |
| Disabled config entries | samsungtv (2), smartthings | `extraComponents`, so they can still be re-enabled |
| YAML (`packages/hatch.yaml`) | template, a `universal` media player, input_select, input_number, scripts, automations, two HomeKit bridges | `extraComponents` for template and universal; the rest come with `default_config` |
| Custom, packaged in nixpkgs | samsungtv_smart 0.14.5 | `home-assistant-custom-components.samsungtv-smart` |
| Custom, not packaged | dyson_local 1.5.7 (vendors libdyson), ha_hatch 1.31.9 (needs `hatch_rest_api` 1.34.5, not in nixpkgs either) | derivations in `custom-components.nix`, pinned by hash |
| Custom, not carried over | HACS 2.0.5; humidity_intelligence 2.1.1 | HACS installs into `custom_components` at runtime, which the module owns. humidity_intelligence has no config entry on Leia, only leftover entities |
| Dashboard cards | none (no `lovelace_resources`) | |
| Blueprints | Home Assistant's bundled four (motion_light, notify_leaving_zone, confirmable_notification, inverted_binary_sensor) | they ship with Home Assistant |

Every name was checked against the pinned package's `availableComponents`, and
the package and all three custom components evaluate. Nothing in the YAML or
the UI-managed files refers to `/share` or to Leia by address, and there are
no USB radios or Bluetooth passthrough.

How the pieces reach each other today, and what changes:

- **Home Assistant reaches the Matter server at `ws://10.10.10.12:5580/ws`**,
  Leia's own address. On Irulan it becomes `ws://localhost:5580/ws`, which is
  an edit to the Matter config entry (step 6 below). The Matter server's port
  stays closed to the LAN.
- **The Matter server's vendor ID.** Leia's runs with the server's default,
  65521, and its fabric was created with it. The nixpkgs module passes Home
  Assistant's, 4939, so the module overrides it back through `extraArgs`.
- **Thread routing already works on Irulan.** It learns the Thread prefix
  (`fdec:a7bd:2c51::/64`) from router advertisements through dhcpcd, where
  Leia carries it as a static route.
- **HomeKit** has 14 bridges on ports 21064–21081, opened with 21063 for the
  next one. Pairings live in `.storage/homekit.*` and move with it. The two in
  `hatch.yaml` are matched by name, so that file moves verbatim.
- **Firewall**: 8123, the HomeKit range, mDNS (5353/udp), and SSDP replies
  (from source port 1900 on the LAN, since connection tracking doesn't relate
  them to the multicast search).
- **Traefik** already routes `homeassistant` to `http://10.10.10.2:8123`, and
  `trusted_proxies` holds Leia's address, plus loopback for Irulan's own
  Traefik (phase 6).

#### Dry run

Proves the service starts, the custom components install and the Matter
server comes up, without touching anything Leia's instance owns. It can't
prove every integration sets up, since an empty config has no config entries
to load; the package build is what guarantees their dependencies are present.

1. On the branch, set `homeAssistant.enable = true` in
   `hosts/irulan/default.nix`, leaving `serveLegacyAddress` off, and push.
   On Irulan, `wt switch home-assistant-native` in `~/.config/system`, then
   `nix-switch` from inside that worktree. The next switch from the main
   checkout puts main back.
2. `journalctl -u home-assistant -u matter-server -b` shows both starting, and
   `ls -l /var/lib/hass/custom_components` the three links. Don't onboard
   through `http://irulan.rolfs.lan:8123`: the cutover replaces this state.
3. `sudo systemctl stop home-assistant matter-server`.

#### Cutover

Home Assistant is down from step 2 to step 8, about as long as the copy takes.

1. **Pin the versions.** On Leia, read both
   (`D=/share/MD0_DATA/.qpkg/container-station/usr/bin/docker`;
   `$D inspect home-assistant --format '{{index .Config.Labels "org.opencontainers.image.version"}}'`,
   `$D exec matter pip show python-matter-server`) and confirm Irulan's are
   the same or newer: `nix eval --raw .#nixosConfigurations.irulan.config.services.home-assistant.package.version`.
2. **Stop Leia's, and keep them stopped.** Home Assistant has
   `restart: always`, so a NAS reboot would bring it back onto `.2`:
   ```sh
   $D update --restart=no home-assistant matter
   $D stop home-assistant matter
   ```
   A Komodo deploy of Leia's stack would also recreate both, so don't deploy
   it until rolfs.lan has them behind a Compose profile (as `leia/komodo` does
   for Core) or removed.
3. **Clear the dry run's state on Irulan.** The dry-run Matter server created
   a fabric of its own, which must not survive:
   ```sh
   sudo systemctl stop home-assistant matter-server
   sudo find /var/lib/hass -mindepth 1 -delete
   sudo find /var/lib/private/matter-server -mindepth 1 -delete
   ```
4. **Copy the Matter server's data.** From an SSH session on Irulan with the
   agent forwarded from the Mac, so Irulan can reach Leia:
   ```sh
   ssh admin@leia 'tar -C /share/Docker/Containers/matter/data -cf - .' \
     | sudo tar -C /var/lib/private/matter-server -xpf -
   ```
   Ownership doesn't matter here: the service runs under `DynamicUser`, and
   systemd hands its state directory to that user when it starts.
5. **Copy Home Assistant's data**, leaving out what the module owns or what
   is specific to the container: `configuration.yaml` and `packages/` (now in
   Nix), `custom_components/` (the module links its own, and would refuse to
   replace real directories), `deps/` (pip installs for the container's
   Python), and logs. `backups/` is left out too, since Backblaze holds the
   copies that matter; include it if a local one should come along.
   ```sh
   ssh admin@leia 'tar -C /share/Docker/Containers/home-assistant/config \
     --exclude=./configuration.yaml --exclude=./packages \
     --exclude=./custom_components --exclude=./deps --exclude=./backups \
     --exclude="./home-assistant.log*" -cf - .' \
     | sudo tar -C /var/lib/hass -xpf -
   sudo chown -R hass:hass /var/lib/hass
   ```
6. **Point the Matter integration at localhost.** With Home Assistant still
   stopped, edit only the URL in its config entry:
   ```sh
   sudo python3 - <<'EOF'
   import json
   p = "/var/lib/hass/.storage/core.config_entries"
   d = json.load(open(p))
   for e in d["data"]["entries"]:
       if e["domain"] == "matter":
           e["data"]["url"] = "ws://localhost:5580/ws"
   json.dump(d, open(p, "w"), indent=4)
   EOF
   sudo chown hass:hass /var/lib/hass/.storage/core.config_entries
   ```
7. **Take the address and start.** Set `serveLegacyAddress = true` beside
   `enable`, commit, and switch. Then announce the address's new MAC, since
   devices still have Leia's macvlan MAC for `.2` cached:
   `nix shell nixpkgs#iputils -c sudo arping -U -I enp3s0 -c 3 10.10.10.2`.
8. **Verify**: `https://homeassistant.rolfs.casa` loads through Traefik; Matter
   devices respond; Apple Home's accessories respond (HomeKit); Hatch, Dyson
   and the Samsung TV integrations are set up; a UI automation fires.
9. **rolfs.lan**: Leia's `home-assistant/` and `matter` services leave the
   Compose file, and `home-assistant/config/` goes with them, since
   `hatch.yaml` now lives here. Keep that as its own commit, after the soak.

**Rollback**, at any step: set both options off and switch (that releases
`.2`), then on Leia `$D update --restart=always home-assistant` and
`--restart=unless-stopped matter`, and `$D start home-assistant matter`.
Leia's data is as of step 2, so changes made on Irulan since are lost unless
copied back the same way.

#### Open for Jamie

- **DLNA renderer events.** The one `dlna_dmr` entry, "Frame Media", is the
  Samsung Frame's built-in renderer, found by SSDP; it is unrelated to Plex or
  the Apple TV, and the Frame's own controls come from `samsungtv_smart`.
  `dlna_dmr` subscribes to the TV's events on a random port, which Irulan's
  firewall drops, so it falls back to polling. Either delete the entry if
  Home Assistant never plays media on the Frame, or set a fixed event listener
  port in its options and open that port here.
- **HACS** isn't carried over. A new custom integration is a derivation in
  `custom-components.nix`, as Dyson and Hatch are.

### Phase 5: Pi-hole

Done 2026-11-01: two Pi-holes instead of one. The primary moved to Irulan as
the Komodo stack `irulan-dns` (rolfs.lan `irulan/dns/compose.yaml`), and
Leia's stayed as a secondary, so DHCP can hand out two filtering resolvers
and either can go down unnoticed. kath stays the upstream for both, and
still forwards over TLS and answers `rolfs.lan` and `rolfs.casa`.

| Role | Address | MAC | Where |
|---|---|---|---|
| Primary | `10.10.10.1` | `02:42:a0:a0:e4:fd` (Kea's reservation) | Irulan, `irulan-dns`, on `irulan-monitoring_lan` |
| Secondary | `10.10.10.3` | `02:42:0a:0a:0a:03`, pinned | Leia, still in `rolfs-casa` |
| Irulan's shim | `10.10.10.4/32` | random | `lan-shim` on Irulan, route to `.1` only |

What to know:

- **The shim** exists because a host can't reach a macvlan container on
  itself. Without it Irulan, and Home Assistant on its network, would time out
  on the first DNS server before falling back. It must answer ARP only for its
  own address (`arp_ignore=1`, set in `hosts/irulan/default.nix`): with the
  default it answered for enp3s0's addresses too, dhcpcd's duplicate-address
  probe took that as a conflict, declined every lease it was offered, and
  Irulan lost `10.10.10.9` mid-cutover. dhcpcd now also skips Docker's
  `veth*`/`br-*` interfaces, one of which it had briefly made the default
  route.
- **One macvlan network per subnet.** Docker refuses a second network for
  `10.10.10.0/24`, so the Pi-hole joins `irulan-monitoring_lan` as an external
  network. A shared LAN network created by the system repo, which every stack
  joins, would decouple the two stacks; worth doing before a third stack needs
  a LAN address.
- **Neither Pi-hole reads a password file.** Both keep only the web
  password's hash, in their own `pihole.toml`; `WEBPASSWORD` matters only when
  setting it. Leia's `pihole.secrets.env` is gone (from Komodo's clone and the
  old checkout), and the one plaintext copy is 1Password's Secrets / Pi-hole,
  field `password`, which both Pi-holes share.
- **nebula-sync runs hourly at :17**, logging in to both with
  `PIHOLE_WEBPASSWORD`: a `komodo.secrets` entry on Irulan synced from that
  1Password item, set in the `irulan-dns` stack's Environment as
  `PIHOLE_WEBPASSWORD=[[PIHOLE_WEBPASSWORD]]`. The compose file reads it as
  `${PIHOLE_WEBPASSWORD:?}`, so a deploy without it fails rather than running
  nebula-sync with no password.
- **Leia's Pi-hole is unfiltered for a minute or two after a restart.** Each
  sync's settings copy restarts its DNS server, which on the NAS reloads 2.9 GB
  of query history before the blocklist is back, and after the cutover's
  recreate it stayed without a blocklist until `pihole reloadlists` (the
  log said "Database not available" for gravity.db while the file itself was
  fine). Clients mostly ask `.1`, so this is minor. Shorter query retention on
  Leia's (`database.maxDBdays`) would shorten it; nebula-sync doesn't touch
  that setting.
- **`10.10.10.9` is on enp3s0 by hand until Kea lets it go.** The declined
  leases left `.9` in Kea's decline quarantine (24 hours by default), so dhcpcd
  holds a pool address (`.151`) and `.9` was added manually to keep
  `irulan.rolfs.lan`, which Komodo and Leia's periphery use, working. A reboot
  before the quarantine ends drops `.9`. After it, `sudo systemctl restart
  dhcpcd` (or a reboot) takes `.9` from the reservation again.

**DHCP: done** (2026-11-01). pfSense hands out `10.10.10.1` and `10.10.10.3`,
with kath dropped, so a client gets filtered answers whichever server it asks.
Clients move over as their 24-hour leases renew.

Rollback: stop `irulan-dns`, then on Leia set the pihole service back to
`10.10.10.1` (drop the pinned MAC) and `docker compose -p rolfs-casa up -d
--no-deps pihole` in Komodo's clone.

### Phase 6: Traefik and step-ca, as a parallel edge (live 2026-11-01)

Traefik fronts every name, so moving Leia's would put everything at risk at
once. Irulan runs a second edge on two new domains instead, and Leia's Traefik,
its step-ca, `rolfs.casa` and `rolfs.lan` stay exactly as they were. With both
working side by side, which names end up on which domain is decided later.

| Domain | Certificates | DNS |
|---|---|---|
| `rolfs.dev` | one Let's Encrypt wildcard (`rolfs.dev`, `*.rolfs.dev`), DNS-01 through Vercel | redirect zone on kath, apex `10.10.10.9` |
| `rolfs.home` | one per name, 24 hours each, from a copy of Leia's step-ca | redirect zone on kath, apex `10.10.10.9` |

Names are flat and the same on both domains: `nas`, `leia`, `kath`, `home`,
`portainer`, `pi`, `plex`, `resilio`, `status`, `komodo`, `traefik`, `nzb`,
`tube`, `sonarr`, `radarr`, `prowlarr`, `torrent`, `qui` and `unpackerr`, so
`plex.rolfs.dev` and `plex.rolfs.home` reach the same server.

The stack is `irulan-edge` in Komodo, from rolfs.lan's `irulan/edge/`:

- **Traefik** runs on Irulan's host network, which `hosts/irulan/default.nix`
  opens 80 and 443 for. Its dashboard is the `traefik` route rather than
  `:8080`, which nebula-sync already holds.
- **Routes come from three providers.** The file provider, in
  `traefik/dynamic/`, has everything that isn't a labelled container:
  Irulan's native services on `127.0.0.1` (Pi-hole at `10.10.10.1`, through
  the `lan-shim`), and the QNAP, kath and Resilio. `common.yml` holds the
  services, middlewares and the wildcard's default certificate store, and
  `rolfs-dev.yml` and `rolfs-home.yml` one router per name, matching name for
  name. The Docker provider reads labels on Irulan's own containers; it was off
  while Traefik was 3.3, whose Docker client asks for API 1.24, below Irulan's
  minimum. The Redis provider carries Leia's containers (below).
- **Leia's containers come through traefik-kop.** A Docker provider only sees
  its own host, so `traefik-kop` on Leia reads the labels its containers carry
  under an `irulan.` prefix and writes them into a Redis on Irulan
  (`services.redis.servers.traefik-kop` in `hosts/irulan/default.nix`), with
  Leia's address and each published port as the backend. Redis has no
  password: Traefik's static configuration can't take one from the
  environment, so the firewall admits Leia alone. Leia's own Traefik reads
  only the unprefixed labels, which keeps its `.lan` step routers away from
  Irulan, where their challenges would fail forever (below). One `irulan.`
  router per service covers both domains, with `tls.domains` limiting the
  step resolver to the `rolfs.home` name.
- **A change to `traefik/traefik.yml` needs a restart**, not just a deploy:
  Compose recreates a container only when the compose file changes, and the
  static configuration is a mounted file. Restart the `traefik` service in
  Komodo after deploying. Dynamic files are watched and apply on the pull.
- **step-ca** is a copy of Leia's `step-ca-data` volume at
  `/srv/edge/step-ca`, taken with Leia's step-ca briefly stopped. Same root,
  same intermediate, same password, so anything that already trusts Leia's
  root trusts `rolfs.home` with nothing new installed. It listens on
  `127.0.0.1:9000` only, which is where Traefik's `step` resolver finds it.
  The two copies share keys but not databases: each records only what it
  issued itself, so a revocation on one is unknown to the other.
- **Home Assistant** trusts `127.0.0.1` and `::1` as proxies now, since
  Traefik reaches it over loopback. Its `.storage/http` holds that, not the
  YAML, as `modules/nixos/services/home-assistant` explains.

Adding a name depends on where it runs. A container on Leia gets `irulan.`
labels beside its others, with a published port, and a container on Irulan
gets ordinary `traefik.` labels. Anything without labels takes a service in
`common.yml` and a router in each of the two domain files. DNS needs nothing, because both zones redirect every name to
Irulan. That is also what keeps `rolfs.home` safe from `rolfs.lan`'s worst
failure: a `step` router whose name doesn't resolve to Traefik fails its
`tlsChallenge` forever and leaks a socket per retry, which is what took Leia's
Traefik to 65,535 open files in October (rolfs.lan's `CLAUDE.md`, "Add the
alias first"). With a redirect zone every name resolves, so it can't happen
while the zone exists. Remove the `-home` routers before ever removing the
zone.

#### Where it stands

Checked on Irulan on 2026-11-02, after traefik-kop:

- **`rolfs.home`**: all 19 names serve, each with its own certificate from
  "Rolfs LAN CA Intermediate CA". Traefik's open files stay flat (25), so no
  challenge is retrying.
- **`rolfs.dev`**: all 19 names serve one Let's Encrypt wildcard
  (`rolfs.dev`, `*.rolfs.dev`), issued 2026-11-02 over Vercel DNS-01 with
  `irulan-edge`'s own token: the `Vercel DNS` item in the Secrets vault, synced
  as the Komodo variable `VERCEL_API_TOKEN` and passed through the stack's
  Environment. Leia's Traefik keeps its own token, so either can be revoked
  alone.
- **Backends**: everything answers as it does through `rolfs.casa` (Plex and
  NZBGet with 401 until signed in, Pi-hole at `/admin/`). Traefik has 22
  routers from the file provider and 8 from Redis, one per labelled container
  on Leia, each backed by `10.10.10.12` and its published port.

#### Toward one edge (decided 2026-11-02)

Irulan's Traefik becomes the only one. No high-availability pair: failing
over between hosts needs a shared address and synchronised certificates, and
buys little when DNS, Home Assistant and Plex already live on Irulan. Leia's
Traefik and step-ca stop once nothing points at them. In order:

1. **Traefik 3.7 with the Docker provider.** Done 2026-11-02 (rolfs.lan
   `cebbc08`). All 38 names answered as before.
2. **traefik-kop.** Done 2026-11-02. Redis on Irulan and Traefik's Redis
   provider (`54c9ded`), then `traefik-kop` and the `irulan.` labels on
   NZBGet, TubeSync, Sonarr, Radarr, Prowlarr, qBittorrent, qui and Unpackerr
   (`d885d46`, which also published Sonarr's, Radarr's and Unpackerr's ports
   and superseded `leia-publish-ports`). Their file-provider entries came out
   afterwards (`3adcfbf`). The three that returned 502 now answer.
3. **The Vercel token.** Done 2026-11-02; the same token will serve a
   `rolfs.casa` wildcard.
4. **`.casa` moves to Irulan.** Done 2026-11-02. Irulan serves all 19 names
   from `rolfs-casa.yml` (rolfs.lan `dc964cd`) under a Let's Encrypt
   `rolfs.casa` wildcard, and kath's zone apex points at `10.10.10.9`. Leia's
   containers are reached through their `@redis` services, so Leia wasn't
   redeployed. The wildcard's first attempt timed out, because the apex and
   the wildcard each need a TXT record on `_acme-challenge.rolfs.casa` and
   Vercel's nameservers were slow to serve the second; `irulan-edge` now gives
   lego ten minutes (`a09a07e`). Leia's Traefik still serves `.casa` to Meter,
   through the NAT, and to anything holding the old answer, whose TTL was a
   day.
5. **`.lan` moves, and Leia's Traefik retires.** Done 2026-11-04. It
   couldn't move sooner: Leia's own `-lan` routers renewed 24-hour step-ca
   certificates daily, and once the names pointed at Irulan every renewal
   would have failed and retried forever. So Leia's `traefik` and `step-ca`
   stopped first, then moved behind a `retired-edge` profile so no deploy
   starts them again (rolfs.lan `03658b7`); the compose file says how to bring
   them back. That also ended `unpackerr-lan`'s failing challenge, a router
   Leia had with no alias behind it. The 14 names became `local-data` lines
   in kath's custom options instead of aliases on the `leia` host override,
   one text block that `kath/network.md` records verbatim. Then the
   `irulan-lan` routers merged (`45d9044`), and every name served its own
   step-ca certificate at once. `leia.rolfs.lan` stays Leia's host name; its
   HTTPS route to the QNAP interface retired with Leia's Traefik, and `nas`
   and `leia` under the other three domains still reach it.
6. **Afterwards**, Leia's containers can carry their `.casa` and `.lan`
   routes in their `irulan.` labels instead of `rolfs-casa.yml` and
   `rolfs-lan.yml`, and lose their unprefixed labels. That needs one more
   `rolfs-casa` deploy and is cleanup, not a step anything waits on. Deleting
   Leia's Traefik, step-ca and the `step-ca-data` volume waits for the usual
   soak, and for Meter's NAT to point at Irulan.

Rollback: stop `irulan-edge` in Komodo. Nothing else depends on it, and the two
domains simply stop answering. Removing kath's `rolfs.dev.` and `rolfs.home.`
zones then takes the names away entirely. Stop the stack before removing the
zones, never the other way round.

### Phase 7: Komodo Core, done ahead of the services

Planned last, but nothing depends on where Core runs, and moving it disturbs
no service: containers are run by each host's Docker, not by Core, so the
cutover costs only a few minutes without the Komodo UI and deploys. It moves
first, with its own runbook: [KOMODO-CORE-CUTOVER.md](KOMODO-CORE-CUTOVER.md).

- **State**: a `mongodump` from Leia restored into Irulan's Mongo, and Core's
  key pair from `/config/keys`. Leia's periphery pins Core's public key
  (`PERIPHERY_CORE_PUBLIC_KEYS`), so a new key pair would lock it out, which is
  why Irulan's Core won't start until Leia's `core.key` is in place.
- **Leia's periphery** changes its core address from `ws://core:9120` to
  `ws://irulan.rolfs.lan:9120`. Leia's `leia/komodo` compose keeps Core and
  Mongo behind a `core` profile, as the rollback.
- **Secrets**: rendered from the `Komodo` 1Password item through
  `onepassword.templates`, not placed by hand.
- **Rollback**: start Core on Leia again. Its database is as of the cutover.
- `/share/Docker/Containers/rolfs.lan` on Leia, the old checkout Leia's Komodo
  stack runs from, still can't go: Leia's periphery runs from it.

## Open questions

- ~Homebridge and vdirsyncer have files in rolfs.lan but no Compose entry. Are
  they running anywhere, and do they move or retire?~ gone.
- Phase 3: move the QPKG's library, or keep the fresh server?
- ~Should Irulan's periphery pin Core's public key, as Leia's does?~ No, not
  while Core is on Irulan. The pin guards the connection's path, and Irulan's
  periphery reaches Core over loopback, where anything able to impersonate
  Core already has the host. Leia's crosses the LAN, which is why it pins. If
  Core ever moves off Irulan, pin it then, with
  `services.komodo-periphery.auth.corePublicKeys` and the key from Core's
  `/config/keys/core.pub`.
