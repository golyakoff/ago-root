# Runbook: backup, and restoring from one

`adr/0050` has the reasoning — what is backed up, what deliberately is not, where the bytes sit, and
why the two numbers are the numbers. This file is the "how", and it is the file that was actually
followed during the drill recorded at the bottom, rather than written afterwards from memory.

**One thing to internalise before anything else.** The file the node writes is **not the backup**. It
is staging. The backup is the copy on a machine the node cannot destroy, and that copy only exists
because the pull ran. A node that dies takes every artifact in its staging directory with it.

Everything below runs as the `ago` user on the node, or in Git Bash on the author's own machine. The
node's address is never written in this repository — `<node-ip>` means it, and the scripts take it as
`AGO_NODE`.

## Parts, and where each one runs

| Part | Runs where | What it is for |
|---|---|---|
| `ago-deploy/k8s/backup/backup.sh` | node, daily at 02:30 UTC | Dumps both databases and the roles, mirrors the MinIO bucket, includes the overlay `.env`, seals the lot into one gpg-encrypted tar, prunes to the newest 7 |
| `ago-deploy/k8s/backup/backup-pull.sh` | the author's machine | Copies new artifacts off the node, verifies their checksums, prunes local copies past 30 days, and fails loudly if the newest is stale. **This is the backup** |
| `ago-deploy/k8s/backup/backup-watchdog.sh` | node, hourly | Mails `alerts@` when the node has stopped producing artifacts, or when the pull has stopped collecting them |
| `ago-deploy/k8s/backup/restore.sh` | wherever the private key is | Decrypts one artifact and restores it into a target Postgres and S3 endpoint given entirely by environment variables |
| `ago-deploy/k8s/backup/docker-compose.restore-drill.yml` | the author's machine | An isolated scratch target: a Postgres, a MinIO, and a Keycloak started **without** `--import-realm` |

## First-time setup

### 1. The key — the author's own act, and the only step a session must not do for you

Whoever holds the private half is the only party who can ever read a backup, and generating it is not
something to delegate. It lives in its own `GNUPGHOME` so it is never mixed into a personal keyring.

```bash
cd ~ && mkdir -p ~/.ago-backup/gnupg && chmod 700 ~/.ago-backup/gnupg
export GNUPGHOME=~/.ago-backup/gnupg
gpg --quick-generate-key 'AGO Platform backup <backup@reserve-me.ru>' rsa4096 encr never
gpg --armor --export backup@reserve-me.ru > ~/.ago-backup/backup-recipient.pub
```

**Put a passphrase on it.** It costs nothing here, because nothing automated ever decrypts — the
backup encrypts, the pull copies ciphertext, and only a human restoring types it:

```bash
cd ~ && GNUPGHOME=~/.ago-backup/gnupg gpg --edit-key backup@reserve-me.ru passwd
```

**Keep a copy of the private key somewhere that is not this laptop.** Lose it and every artifact ever
taken is permanently unreadable — there is no escrow and no recovery path. `17-03` owns rotation and
should carry this key in its inventory.

```bash
cd ~ && GNUPGHOME=~/.ago-backup/gnupg gpg --armor --export-secret-keys backup@reserve-me.ru > /path/to/offline/media/ago-backup-key.asc
```

### 2. Install on the node

Only the **public** half goes to the node. `backup.sh` refuses to run without it, rather than writing
something nobody can decrypt.

```bash
cd ~ && scp -i ~/.ssh/ago-vps-ed25519 ~/.ago-backup/backup-recipient.pub ago@<node-ip>:~/ago/backup-recipient.pub
ssh -i ~/.ssh/ago-vps-ed25519 ago@<node-ip>
```

then, on the node:

```bash
cd ~/ago/ago-deploy && git pull --ff-only origin main && k8s/backup/install-node.sh
```

That copies the four systemd units into `/etc/systemd/system`, enables both timers, and prints when
they next fire. It is idempotent — re-run it after every `git pull` that touches `k8s/backup/`.

> `./redeploy.sh` does **not** carry this. That script pulls, builds, migrates and restarts; it never
> installs a systemd unit and never runs `kubectl apply -k`. A change under `k8s/backup/` reaches the
> node through `install-node.sh` and nothing else — see [`redeploy.md`](redeploy.md)'s own "What it
> does not apply" section, which is the same trap in a different costume.

### 3. Schedule the pull on the author's machine

```bash
cd ~/ago/ago-deploy/k8s/backup && AGO_NODE=<node-ip> ./backup-pull.sh
```

Run it once by hand first — it prints what it pulled and how old the newest copy is. Then schedule it
daily (Windows Task Scheduler, or whatever is already scheduling things on that machine). Exit code 2
means "the newest artifact is older than it should be" and is worth surfacing rather than swallowing.

Defaults, all overridable by environment variable: `AGO_BACKUP_LOCAL_DIR=~/ago-backups`,
`AGO_BACKUP_KEEP_DAYS=30`, `AGO_BACKUP_STALE_HOURS=30`.

## Taking a backup by hand

```bash
cd ~ && ssh -i ~/.ssh/ago-vps-ed25519 ago@<node-ip> '~/ago/ago-deploy/k8s/backup/backup.sh'
```

Or through systemd, which additionally proves the unit rather than only the script:

```bash
cd ~ && ssh -i ~/.ssh/ago-vps-ed25519 ago@<node-ip> 'sudo systemctl start ago-backup.service && journalctl -u ago-backup.service -n 10 --no-pager'
```

## Restoring

**Never over the live databases.** `restore.sh` has no default target for exactly this reason: every
connection detail is an environment variable and there is nothing to forget to override. Restoring
into production is a separate, deliberate act with its own decision to make about what is already
there — this procedure gets the data back where it can be looked at.

### 1. Bring up a scratch target

```bash
cd ~/ago/ago-deploy/k8s/backup
docker compose -p ago-restore-drill -f docker-compose.restore-drill.yml up -d
```

Three containers on their own network and their own ports (`15433`, `19000`, `18081`) — nothing shared
with `docker/docker-compose.yml`'s local dev loop. Keycloak will fail to start until the `keycloak`
database exists; that is expected, and step 3 restarts it.

### 2. Restore

```bash
cd ~/ago/ago-deploy/k8s/backup
export GNUPGHOME=~/.ago-backup/gnupg
export PGHOST=postgres PGPORT=5432 PGUSER=ago PGPASSWORD=drill-only-not-a-secret
export S3_ENDPOINT=http://minio:9000 S3_ACCESS_KEY=drilluser S3_SECRET_KEY=drill-only-not-a-secret
export KEYCLOAK_DB_SCRATCH_PASSWORD=drill-only-not-a-secret
./restore.sh ~/ago-backups/ago-backup-<stamp>.tar.gpg
```

It prints the manifest sealed inside the artifact — including the row counts as they were **at dump
time** — and then the row counts it produced. Those two blocks are the first check, and they must
match.

`PGHOST=postgres` is a container name, not a hostname on your machine: the psql and mc containers join
the drill's own docker network. Restoring to something else means setting `DOCKER_NETWORK` too.

### 3. Prove it, rather than believing the exit code

Restart Keycloak so it boots against the restored database:

```bash
cd ~/ago/ago-deploy/k8s/backup
docker compose -p ago-restore-drill -f docker-compose.restore-drill.yml restart keycloak
curl -s http://localhost:18081/realms/ago-chat | head -c 120
```

The realm answering here is already evidence: that Keycloak runs **without `--import-realm`**, so the
realm, its client and its signing keys have nowhere to come from except the database that was just
restored.

Then the three things `backlog/15-02` insists on checking rather than assuming:

```bash
# A real login, against the restored credential store
cd ~ && curl -s -X POST http://localhost:18081/realms/ago-chat/protocol/openid-connect/token \
  -d "grant_type=password&client_id=ago-console&username=demo-operator&password=demo-operator-password" \
  | grep -c access_token

# A specific conversation's history, in order, out of the restored database
cd ~ && MSYS_NO_PATHCONV=1 docker run --rm --network ago-restore-drill_default \
  -e PGPASSWORD=drill-only-not-a-secret postgres:17-alpine \
  psql -h postgres -U ago -d ago_chat -c \
  "select sequence, author_kind, length(body), tableoid::regclass as partition
     from messages where conversation_id='<a conversation id>' order by sequence"

# An attachment's actual bytes
cd ~ && MSYS_NO_PATHCONV=1 docker run --rm --network ago-restore-drill_default \
  -e MC_HOST_t=http://drilluser:drill-only-not-a-secret@minio:9000 \
  --entrypoint /bin/sh minio/mc:latest -c "mc ls --recursive t/attachments; mc cat t/attachments/<object key> | sha256sum"
```

### 4. Tear it down, and mean it

```bash
cd ~/ago/ago-deploy/k8s/backup
docker compose -p ago-restore-drill -f docker-compose.restore-drill.yml down -v
```

`-v` removes the volumes. That is required, not tidiness: a scratch target left running is a second
copy of every visitor's messages sitting on a laptop, outside the retention window the pull enforces
on the artifacts themselves.

## Restoring onto a rebuilt node

The drill above proves the data comes back. Putting it back into a running deployment adds these, in
this order, and none of them is exercised by the drill:

1. Rebuild the cluster to the point where the workloads *would* start — `public-deploy.md` steps 3–8,
   with `15-06`/`adr/0047` supplying the images.
2. Restore the overlay's `.env` from inside the artifact **before** applying the overlay, so the
   `secretGenerator` produces the same values the restored data expects — in particular
   `KEYCLOAK_DB_PASSWORD`, which must match the password hash the restored `keycloak` role carries, and
   `AUTH_JWT_SIGNING_KEY`, whose loss invalidates every outstanding visitor token.
3. Restore into the cluster's Postgres **before** Keycloak first starts, or Keycloak will initialise an
   empty schema and the restore will then be fighting it.
4. Do **not** run `dotnet ef database update` afterwards expecting it to do anything: the restored
   database already carries `__EFMigrationsHistory`. Run it to confirm it reports nothing to do.
5. Create the MinIO bucket if the restore did not (`mc mb --ignore-existing`), then mirror the objects
   in. Nothing in `ago-deploy` provisions that bucket — see the gap below.
6. `smoke.sh` last, as `redeploy.md` has it.

**If the restore was performed because an artifact may have been exposed, rotate every credential
afterwards** (`17-03`). The artifact contains the overlay's `.env`; `adr/0050` records why that is
deliberate and what it costs.

## The drill that was actually performed — 2026-08-25

Real backup of the real deployment, restored into an isolated scratch stack on the author's machine,
with everything below observed rather than expected.

**Timings, wall clock:**

| Step | Time |
|---|---|
| `backup.sh` on the node, whole run | **4–5 s** (three separate runs: 4 s, 4 s, 5 s) |
| `backup-pull.sh`, one artifact over the internet | **2 s** (three runs, all 2 s) |
| `restore.sh`, decrypt through verified row counts | **14 s and 17 s** (two full runs, two different artifacts) |
| Keycloak booting against the restored database | **~9 s** to a 200 on the realm endpoint, both runs |

The drill was run twice, deliberately: once while the scripts were being debugged, and once more from
scratch **with the final committed scripts**, so that what this file claims was followed is the code
that is in the repository rather than a near-miss of it. The second run additionally caught something
worth seeing — `attachments` came back as **1** row rather than 2, because the worker's orphan sweeper
had deleted the unconfirmed `Pending` row between the two backups (`AttachmentOrphanSweepJob`, 10 min
`UploadLifetime`). The backup tracked a real deletion rather than preserving a stale count.

**Size:** one encrypted artifact is **1 132 198 bytes (1.08 MB)**. Inside it: `ago_chat.dump`
1 098 852 B, `keycloak.dump` 212 087 B, `overlay.env` 2 622 B, `manifest.txt` 1 309 B, `globals.sql`
930 B, one MinIO object 69 B. gpg does not compress further — `pg_dump -Fc` already has.

`ago_chat.dump` is dominated by `outbox`, which held **18 634 rows** and has never had a row deleted
(`personal-data.md`: nothing here is pruned). Against 17 messages in the same database. **The
outbox grew by roughly 14 000 rows in one day**, so it — not conversation history — is what will drive
both backup size and disk growth until `15-04` exists. `15-05` should start there.

**What was verified after the restore, and how:**

| Claim | Evidence |
|---|---|
| Row counts survive | Restored `ago_chat`: conversations 10, messages 17, attachments 2, visitors 10, sites 2, operators 3, outbox 18 634 — **each identical to the manifest's own dump-time counts**. Restored `keycloak`: 4 users, matching. (Second run, later artifact: identical except attachments 1 and outbox 18 702, both matching *its* manifest) |
| Partitioning survives | `messages` came back as a partitioned table, `PARTITION KEY RANGE (created_at)`, 3 partitions, with `adr/0019`'s widened unique indexes intact. All 17 rows routed to `messages_2026_08`. `pg_dump`/`pg_restore` needed no partition-aware special handling |
| A specific conversation is readable | Conversation `01a034d2-…` came back with all 13 messages, correct `sequence` order 1–13, correct `Operator`/`Visitor` alternation, Cyrillic bodies intact byte for byte |
| An attachment's bytes are retrievable | A 69-byte PNG uploaded through the **real public API** (presigned PUT, then confirm) before the backup. After the restore its object read back with sha256 `c9945e20…b291` — **identical to the bytes originally uploaded** |
| A Keycloak account can authenticate | `demo-operator` obtained a real access token from the drill Keycloak, which was started **without `--import-realm`**. Its `sub` claim came back as `…0004` |
| The cross-database link survives | That same `…0004` is `operators.external_subject_id` for operator `…0002` in the restored `ago_chat` — the one pointer that crosses the two dumps, intact |
| Non-seeded data survives | The restored realm holds 4 accounts, of which 3 are seeded demo users. The fourth — created through `10-01`'s self-registration on the live deployment — restored intact. Its username is deliberately not written here |
| Pruning happens by something, not by hand | A run with `AGO_BACKUP_KEEP=2` deleted the oldest artifact **and** its checksum sidecar, leaving exactly two |
| The watchdog actually mails a person | With no pull yet recorded, it delivered a real DKIM-signed message through the node's Postfix to `alerts@`, naming the missing marker. After a successful pull, the same script sent nothing |

**Three real bugs the drill found, all in this item's own code, all fixed:**

1. Three levels of shell quoting in the manifest's row-count query produced `syntax error at or near
   "||"`. Fixed by letting `psql -F=` do the formatting instead of building the string in SQL.
2. `backup-pull.sh` pulled only the **first** artifact and reported success. `ssh` inside the download
   loop was consuming the loop's own stdin. Fixed with `ssh -n`. Worth remembering: it looked exactly
   like a working pull.
3. `pg_dumpall --globals-only` includes `ALTER ROLE ago … PASSWORD '<the node's hash>'`, and `ago` is
   the role `restore.sh` connects as — so applying globals locked the script out of its own scratch
   target with `password authentication failed`. Fixed by appending the reset to the same file so it
   runs in the same psql session, which is the only place it can work.

**A real gap found on the live deployment while doing this, and closed:** MinIO had **no bucket at
all**. Every attachment upload on the public deployment would have failed, and nobody had noticed
because nobody had tried one. `attachments` was created by hand and the whole path — presign, PUT,
confirm, download — verified end to end there for the first time. `file-storage.md` has the standing
half of that gap: nothing in `ago-deploy` provisions the bucket, so a rebuilt cluster still starts
without one.

## Troubleshooting

- **`backup.sh` exits with "no recipient public key"** — `~/ago/backup-recipient.pub` is missing on
  the node. Setup step 2. It is a deliberate refusal, not a bug: the alternative is writing artifacts
  nobody can read.
- **The pull reports a checksum mismatch** — the transfer was truncated. Re-run it; the partial file
  is removed, and a `.part` left behind is safe to delete.
- **`restore.sh` fails with `password authentication failed`** — a previous run applied globals
  without the reset. Tear the scratch stack down with `down -v` and start again; there is no way to
  recover a target whose superuser password was replaced by a hash you do not have.
- **Keycloak in the drill stays unhealthy** — it started before the `keycloak` database existed.
  Restart it after the restore, not before.
- **`docker run` fails with `exec: "C:/Program Files/Git/usr/bin/sh"`** — MSYS rewrote the container's
  own path. Prefix the command with `MSYS_NO_PATHCONV=1`. `restore.sh` already does this internally.
- **No alert mail ever arrives** — check the alias first (`grep alerts /etc/aliases`), then
  `journalctl -u postfix`. [`alerting.md`](alerting.md) owns that path.
