# Moving Komodo Core from Leia to Irulan

Core and its Mongo move to Irulan. Every service stays where it is: containers
are started and kept running by each host's Docker, not by Core, so while Core
is down nothing but the Komodo UI and deploys are unavailable. Expect a few
minutes of that, from step 3 to step 7.

Two branches carry the change, both named `komodo-core-irulan`:

- **system repo**: `komodo.core.enable` on Irulan, with credentials rendered
  from the `Komodo` 1Password item. Mongo starts on the next switch; Core waits
  for `komodo.core.activate` and for Leia's `core.key` to be in place.
- **rolfs.lan**: Traefik's `komodo` backend pointed at
  `irulan.rolfs.lan:9120`, and `leia/komodo/` reduced to the periphery, with
  Core and Mongo behind a `core` profile for rollback.

Commands marked **Leia** run in `ssh leia`, **Irulan** in `ssh irulan`, and
**Mac** on a machine with both of those SSH hosts configured.

## Before you start

1. **Irulan is a Server in Komodo, and accepted.** Its periphery has been
   connecting since phase 1. If Komodo's Servers page shows `irulan` with an
   attempted key, accept it now, so the database you are about to copy already
   trusts it.
2. **Irulan has a fixed address.** Leia's periphery and Traefik reach Core by
   `irulan.rolfs.lan`, so give Irulan a DHCP static mapping in pfSense first
   (the migration plan suggests `10.10.10.14`). Check from Leia:
   `getent hosts irulan.rolfs.lan`.
3. **Pin Core's version to Leia's.** The restored database has to be read by
   the same release that wrote it, or a newer one.

   **Leia:**

   ```sh
   docker inspect komodo-core --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'
   docker inspect komodo-core --format '{{ .Config.Image }} {{ .Image }}'
   ```

   Set `komodo.core.imageTag` in `hosts/irulan/default.nix` to that exact
   version (for example `"2.3.3"`), rather than the floating `2`. Keep it at
   or above Irulan's periphery, which is nixpkgs' `komodo-periphery` (2.3.3 at
   the time of writing).
4. **Check the database name.** Komodo's default is `komodo`.

   **Leia:**

   ```sh
   docker exec komodo-mongo sh -c 'exec mongo --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "db.adminCommand({ listDatabases: 1 }).databases.map(d => d.name)"'
   ```

   If it isn't `komodo`, use its name in place of `komodo` in step 4 below.
   The credentials are read inside the container from its own environment, so
   they never appear on your terminal or in your shell history.

## The cutover

### 1. Merge the system branch, and let Irulan start Mongo

Merge `komodo-core-irulan` into `main` in the system repo, with the image tag
pinned. **Irulan:**

```sh
nix-switch --pull
docker ps --filter name=komodo          # komodo-mongo running, no komodo-core
systemctl status docker-komodo-core     # inactive, and enabled for nothing
```

The new Mongo is empty, with its root user created from the 1Password
credentials, the same ones Leia's database uses.

*Rollback:* nothing to undo on Leia. Setting `komodo.core.enable = false`
removes Mongo again.

### 2. Merge nothing in rolfs.lan yet

Its branch changes Traefik's route as soon as Komodo's clone on Leia pulls it,
which would send `komodo.rolfs.casa` to an Irulan with no Core. It merges in
step 7.

### 3. Stop Core on Leia

From here the Komodo UI is unavailable until step 7. **Leia:**

```sh
docker stop komodo-core
```

Only Core stops. Leia's Mongo keeps running for the dump, and Leia's periphery
keeps running too; it just loses its connection.

*Rollback:* `docker start komodo-core`.

### 4. Dump the database and copy Core's keys

**Leia:**

```sh
mkdir -p /share/Docker/Containers/komodo/cutover
cd /share/Docker/Containers/komodo/cutover

docker exec komodo-mongo sh -c 'exec mongodump --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db komodo --archive --gzip' > komodo.archive.gz

# Works on the stopped container. This is the komodo-keys volume, shared by
# Core and Leia's periphery.
docker cp komodo-core:/config/keys ./keys

ls -l komodo.archive.gz keys/
```

Expect `core.key` and `core.pub` in `keys/`, probably `periphery.key` and
`periphery.pub` too. Only Core's pair and `periphery.pub` move to Irulan;
`periphery.key` is Leia's periphery's own private key and stays on Leia.

**Mac:**

```sh
ssh irulan 'install -d -m 0700 /tmp/komodo-cutover'
scp -3 leia:/share/Docker/Containers/komodo/cutover/komodo.archive.gz irulan:/tmp/komodo-cutover/
scp -3 'leia:/share/Docker/Containers/komodo/cutover/keys/core.*' irulan:/tmp/komodo-cutover/
scp -3 leia:/share/Docker/Containers/komodo/cutover/keys/periphery.pub irulan:/tmp/komodo-cutover/
```

`-3` relays through the Mac, so neither server needs SSH access to the other.
Skip the last line if Leia has no `periphery.pub`.

*Rollback:* nothing changed yet. `docker start komodo-core` on Leia.

### 5. Restore into Irulan's Mongo, then place the keys

Restore first: Core can't start before its key is in place (the unit's
`ConditionPathExists`), so placing the key last means it can never meet an
empty database. **Irulan:**

```sh
docker exec -i komodo-mongo sh -c 'exec mongorestore --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --drop' < /tmp/komodo-cutover/komodo.archive.gz

sudo install -m 0600 -o root -g root /tmp/komodo-cutover/core.key /var/lib/komodo/keys/
sudo install -m 0644 -o root -g root /tmp/komodo-cutover/core.pub /var/lib/komodo/keys/
sudo install -m 0644 -o root -g root /tmp/komodo-cutover/periphery.pub /var/lib/komodo/keys/   # if copied
sudo ls -l /var/lib/komodo/keys
```

*Rollback:* `docker start komodo-core` on Leia. Irulan's copies are harmless
while `activate` is off.

### 6. Start Core on Irulan

Set `komodo.core.activate = true` in `hosts/irulan/default.nix`, commit and
push. **Irulan:**

```sh
nix-switch --pull
systemctl status docker-komodo-core
docker logs --tail 50 komodo-core
```

This also moves Irulan's periphery to `ws://127.0.0.1:9120`. Open
`http://irulan.rolfs.lan:9120` and log in as before: users come with the
database. `irulan` should show as connected; `leia` as disconnected until the
next step.

*Rollback:* set `activate` back to `false` and switch (Core stops, Irulan's
periphery goes back to `https://komodo.rolfs.casa`), then
`docker start komodo-core` on Leia. Anything changed in the new Core is lost.

### 7. Repoint Leia's periphery, then Traefik

Merge rolfs.lan's `komodo-core-irulan` into `main`.

Leia's Komodo stack is not deployed by Komodo: it runs from the old pre-Komodo
checkout at `/share/Docker/Containers/rolfs.lan`, by hand. That checkout is
far behind `main`, so take only the two files. **Leia:**

```sh
cd /share/Docker/Containers/rolfs.lan/leia/komodo
cp docker-compose.yml docker-compose.yml.pre-irulan
cp komodo.env komodo.env.pre-irulan
git fetch origin
git checkout origin/main -- docker-compose.yml komodo.env
docker compose up -d              # recreates the periphery only
docker stop komodo-mongo          # stopped, not removed: it's the rollback
```

In the UI, `leia` turns green. Then Traefik, whose file provider reads
`servers.yml` from Komodo's clone of the repo. A pull is enough, nothing needs
redeploying. **Leia:**

```sh
git -C /share/Docker/Containers/komodo/data/repos/rolfs.lan pull --ff-only
```

(If Komodo already pulled the merge on its own, this is a no-op.)
`https://komodo.rolfs.casa` now opens Irulan's Core.

*Rollback:*

```sh
cd /share/Docker/Containers/rolfs.lan/leia/komodo
mv docker-compose.yml.pre-irulan docker-compose.yml
mv komodo.env.pre-irulan komodo.env
docker compose up -d
```

then revert the Traefik commit on rolfs.lan's `main` and pull in Komodo's
clone again, and do step 6's rollback on Irulan.

### 8. Check, then clean up

- Both servers are connected on the Servers page.
- A harmless action reaches each host: **Pull** on one of Leia's stacks, and
  on Irulan any stack or the server's stats.
- **Backup Core Database** (Procedures) writes to `/var/lib/komodo/backups`
  on Irulan.

Then delete the copies, since the archive holds Komodo's users and stored
secrets. **Leia:** `rm -rf /share/Docker/Containers/komodo/cutover`.
**Irulan:** `rm -rf /tmp/komodo-cutover`.

Leave Leia's stopped `komodo-core` and `komodo-mongo` containers, and their
volumes, for a couple of weeks of soak. Removing them after that is
`docker rm komodo-core komodo-mongo` in `leia/komodo`, keeping the
`komodo-keys` volume, which Leia's periphery still uses.

## What stays the same

- **Leia's periphery keeps its key and its pinning.** It still reads its own
  private key and Core's public key from the `komodo-keys` volume; only its
  core address changes. That's why Core's key pair moves rather than being
  generated.
- **The old checkout on Leia stays.** Leia's periphery runs from it, so
  `/share/Docker/Containers/rolfs.lan` is still load-bearing.
- **Irulan's periphery doesn't pin Core's key** (an open question in
  [IRULAN-MIGRATION.md](IRULAN-MIGRATION.md)). Now that Core's public key sits
  at `/var/lib/komodo/keys/core.pub` on the same host, pinning it is a one-line
  `services.komodo-periphery.auth.corePublicKeys`.
