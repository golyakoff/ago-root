# ADR-0050: What is backed up, where the bytes go, and who can read them

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 15

## Context

The public deployment holds real data. Not "demo data with a real domain in front of it" — two demo
tenants' conversations, one account a stranger created through `10-01`'s self-registration flow, and
an attachment uploaded through the real API. All of it sits on one node's local-path volumes
(`adr/0026`), and until this decision nothing copied any of it anywhere.

Three inputs shaped what this had to cover, and two of them are recent enough that an earlier version
of this decision would have got them wrong.

**`architecture/personal-data.md` (rewritten and verified against the code by `16-01`, 2026-08-25) is
the inventory.** It establishes that message bodies are the bulk of the personal data here and cannot
be minimised by choosing fields; that Keycloak's user store is now persistent and lives in its own
`keycloak` database inside the same Postgres (`adr/0036`, `15-01`); that Redis snapshots its keyspace
to a PVC; and that **message bodies cross the broker** and can sit indefinitely in leaked, durable
`deliver-to-connections.{node}` queues. It also establishes the blunt fact that governs everything
below: **nothing in this system is ever deleted automatically, anywhere**, except Redis TTLs and the
attachment orphan sweep.

**Residency is a standing constraint, not a preference.** `personal-data.md`'s "Data residency"
section names `15-02` explicitly as the item that could make "the single largest transfer this project
could make", and sets the default answer for any new destination to "in Russia", with a move out
being a decision made in writing with the legal question asked first.

**The destination was already decided by the author on 2026-08-25** and recorded in `backlog/15-02`:
the author's own machine, pulled over the SSH access that already exists. This ADR records that
decision with the alternatives it beat rather than re-opening it, and decides the three things it
left open — scope per store, encryption, and the two numbers.

`nfr.md` has no availability SLA and `backlog/15-02` puts an RPO/RTO commitment explicitly out of
scope, so nothing here is derived from a recovery-time target. Where a number is a choice, it says so.

## Decision

### 1. Per store: backed up, or recreatable and why

| Store | Decision | Why |
|---|---|---|
| Postgres `ago_chat` | **Backed up** — `pg_dump -Fc` | Conversations, messages, attachment rows, sites, operators, outbox. Rebuildable from nothing else. |
| Postgres `keycloak` | **Backed up** — `pg_dump -Fc` | Since `15-01`/`adr/0036` this is where accounts, credentials, sessions and the realm's own signing keys live. A backup taken before `15-01` would have been backing up two thirds of the system and calling it a backup. |
| Postgres roles | **Backed up** — `pg_dumpall --globals-only` | The `keycloak` role is created by an init container, not by a migration; without it a restored `keycloak` database has an owner that does not exist. |
| MinIO `attachments` | **Backed up** — object-level `mc mirror` | A database dump alone is not a restore (`file-storage.md`): the `attachments` rows point at bytes that live only here. |
| The demo overlay's `.env` | **Backed up** | See consequence 3 — this is the inclusion with a real cost, made deliberately. |
| Redis | **Not backed up.** Recreatable | Cache, rate-limit buckets, presence and the connection registry — never a source of truth (`adr/0009`, `caching.md`), and `realtime.md`'s degradation path already states it may be lost. There is a second reason that points the same way: the PVC's RDB snapshot contains a rate-limit bucket keyed by **client IP**, so *not* copying it is also the privacy-preferable answer. |
| RabbitMQ | **Not backed up.** Recoverable by consequence, not by replay | This is the entry `personal-data.md` makes non-obvious, so the reasoning is spelled out rather than asserted. Outbox-published events are replayable from `outbox` by construction. Node fan-out deliveries are **not** — they bypass the outbox (`adr/0020`) and their `NodeDelivery.PayloadJson` carries full message bodies. But losing one costs a live push, not a message: the message itself is already committed in Postgres and the client re-reads history on reconnect. **And backing the queues up would be actively harmful**: it would copy the message text stranded in leaked node queues into every artifact and extend its life to the backup retention window, converting a bounded leak into a replicated one. Excluding it is both the operationally correct and the privacy-correct answer. |
| Prometheus, Grafana, Alertmanager | **Not backed up.** Out of scope per `backlog/15-02`; Grafana's dashboards and datasources are provisioned from ConfigMaps in `ago-deploy`, so they are recreatable from git rather than merely expendable |
| Jaeger | **Not backed up.** In-memory by configuration (`k8s/base/jaeger.yaml`), destroyed by every pod restart already |
| Manifests, images | **Not backed up here.** `ago-deploy` is in git; `15-06`/`adr/0047` is what makes a rebuilt cluster able to pull identifiable images. That item and this one are two halves of one story — images without data is not a recovery, and data without images is not one either |

### 2. The destination, and why the staged copy is not the backup

**Staging on the node, pulled to the author's own machine over the existing SSH key.** No paid
service, no new daemon, no new inbound port, no third party holding a copy of every visitor's
messages.

The artifact `backup.sh` writes on the node is **not** the backup. It is staging. A same-host copy
covers operator and software error, which is real and is not the failure this exists for: a dead disk,
a suspended account, a compromised root. The backup is the copy on a machine the node cannot destroy,
and `backup-pull.sh` is the step that creates it.

No SFTP daemon is added. SSH already is one, and `17-05` closed the firewall on the same day this was
being written; reopening surface to duplicate a channel that already exists would be a poor trade.

### 3. Encryption: public-key, and the private half is never on the node

Every artifact is encrypted with **GnuPG public-key encryption** to a recipient key whose private half
is generated on, and never leaves, the machine that holds the backups.

GnuPG rather than `age` or `restic` because it is already installed on both ends — Ubuntu's base
install on the node, Git Bash's own on the author's Windows machine — and this is the one mechanism
that has to work on a bad day without a package manager.

Public-key rather than a symmetric passphrase, for two properties that are the point:

- **An attacker who owns the node can read the live database but cannot read the backup history.**
  The node holds only the public half. That is not a large win — the live database is the same data —
  but it costs nothing.
- **Nothing automated ever decrypts.** The backup encrypts, the pull copies ciphertext, and only a
  human performing a restore decrypts. That is what makes it free to put a passphrase on the private
  key: no scheduled task ever has to supply it.

**Where the key lives**: `~/.ago-backup/gnupg` on the author's machine, in its own `GNUPGHOME` so it
is not mixed into a personal keyring. `17-03` owns rotation and should treat this key as one of the
values it inventories.

**The cost, stated because it is the real one**: lose that private key and every artifact ever taken
is permanently unreadable. There is no escrow and no recovery. A copy of the identity file kept
offline is the mitigation, and it is the author's to make.

### 4. Frequency: daily, and the reason is the pull, not the dump

**Daily, at 02:30 UTC**, with `Persistent=true` so a reboot spanning the window does not silently skip
a day.

Measured on 2026-08-25 against the real deployment: a full backup run takes **4–5 seconds** and
produces a **1.08 MB** encrypted artifact. At that cost, hourly would also be nearly free — so the
schedule is not bounded by what the dump costs.

It is bounded by the pull. An artifact that has not been collected is not a backup, and the collector
is a personal machine that is not always on. Backing up more often than it can be collected buys a
fuller staging directory and nothing else. **The honest statement of the recovery point is therefore
"since the last time the author's machine was on and ran the pull", not "since 02:30 UTC"** — which
is exactly why `backlog/15-02` refused to state an RPO, and why the freshness watchdog below exists.

If the destination ever becomes something always-on, this is the first line to revisit.

### 5. Retention: 30 days, on both sides — and this is a choice, not a derivation

**30 days on the collected copies. 7 runs in the node's staging directory.**

Neither is derived, and pretending otherwise would be the failure `CLAUDE.md` forbids. What can
honestly be said:

- **The window is a privacy mechanism before it is an operational one.** `personal-data.md`'s
  "Deletion versus backups" resolves the contradiction between erasure and restorability by bounding
  how long a copy survives, so that "we deleted it" becomes true rather than aspirational. Copies
  sitting on a personal disk indefinitely would make that statement false. The alternative it
  considered and rejected — a deletion journal replayed after every restore — is more precise and is
  itself a list of people who asked to be forgotten.
- **It must equal whatever the published privacy policy states**, and that policy does not exist yet.
  30 days is a placeholder chosen to be defensible and short, and it is set in exactly one place
  (`AGO_BACKUP_KEEP_DAYS`) so that aligning it later is one edit, not a hunt.
- **It is not the same number as `adr/0031`'s history window**, which is deliberately unset until
  `15-05` measures storage growth. Conflating them would be convenient and wrong: one bounds how long
  a copy of deleted data survives, the other bounds how long live history is kept.
- The node-side bound is a **count** rather than an age, because staging exists to let a pull catch up
  after missed days and a count is the bound that does not depend on the timer having run.

### 6. Freshness is watched from the node, by mail, reusing `adr/0045`

The weak point of this whole design is that it depends on a machine being switched on and a scheduled
task not having quietly failed — and silence looks exactly like success.

Two halves, because neither covers the other:

- `backup-pull.sh` fails loudly and non-zero when the newest artifact it can see is stale.
- A **node-side watchdog** runs hourly and mails a person when the newest artifact on the node is
  older than 30 h, or when the last successful pull is older than 72 h. The pull touches a marker file
  on the node when it succeeds, which is what makes its *absence* visible from the node at all — a
  machine that is switched off cannot report that it is switched off.

Delivery reuses `adr/0045`'s path exactly: the node's own Postfix, to the `alerts@` alias that
`/etc/aliases` expands to a real mailbox held in no repository. No Prometheus rule, no Alertmanager
route, no manifest change — a systemd timer and `sendmail`. The alternative, a node-exporter textfile
metric plus an alert rule, would have been more uniform with `15-03` and needed a change to
`node-exporter.yaml`'s collector set plus a new rule, for a check with exactly one consumer.

**What it cannot do**: report that the node is dead. That is `15-03`'s external check, which exists.

## Consequences

- **A restore has been performed, so the numbers in `docs/runbooks/backup-and-restore.md` are
  measurements rather than estimates.** Backup 4–5 s; pull 2 s; full restore into an empty scratch
  stack, from decryption to verified data, **14–17 s** across two complete runs. At this data size the
  recovery cost is dominated
  by bringing a cluster up, not by moving data — which is `15-06`'s subject and is where any future
  effort belongs.
- **The recovery point is bounded by a personal machine's uptime.** Stated above, restated here,
  because it is the honest limit of the arrangement the author chose and it should be read every time
  someone asks how much data a lost node would cost.
- **There is no cross-database consistency.** `ago_chat` and `keycloak` are dumped in separate
  snapshots seconds apart, because Postgres cannot dump two databases in one transaction at all. The
  single place it can bite is `operators.external_subject_id`, which points at a Keycloak user id: an
  account created in that window can restore as an operator row whose Keycloak user is missing, or the
  reverse. Both are repairable by hand and neither is silent.
- **A leaked artifact is now a live credential breach as well as a data breach.** The overlay's `.env`
  is included, and that is a genuine escalation: data in a stolen backup is historical, credentials in
  one are a way into the running system. It is included anyway because a restore without it does not
  work under pressure — `AUTH_JWT_SIGNING_KEY` regenerating invalidates every outstanding visitor
  token, and `KEYCLOAK_DB_PASSWORD` must match the password hash the restored `keycloak` role carries
  or Keycloak will not start. The standing consequence: **a restore performed because an artifact may
  have been exposed is followed by a credential rotation** (`17-03`).
- **`pg_dumpall --globals-only` carries role password hashes**, which is a second reason the artifact
  is encrypted rather than merely private, and a trap during restore: applying globals to a scratch
  target silently replaces that target's own superuser password with the source's. `restore.sh` resets
  it inside the same psql session, which is the only place the reset can work.
- **`personal-data.md`'s Backups row stops being open.** It gains a control, a window and a removal
  path, which is what that row was waiting for.
- **The MinIO bucket gap that `file-storage.md` has flagged twice is now half closed.** It was found
  live by this item: the public deployment had **no bucket at all**, so every attachment upload there
  would have failed, and nobody had noticed because nobody had tried. The bucket was created by hand
  and the whole attachment path verified end to end for the first time on that deployment. The other
  half is unchanged — nothing in `ago-deploy` provisions it, so a rebuilt cluster still starts without
  one.
- **Two things now have to be maintained**: a shell script that knows the shape of the deployment
  (which secret carries MinIO's credentials, which databases exist), and a restore drill that has to
  be re-run when that shape changes. A backup verified once and never again decays into a hypothesis
  at the speed the system changes.

## Alternatives considered

- **A managed object-storage bucket (Yandex Object Storage, S3, Backblaze B2) as the destination.**
  The conventional answer, and the one that removes the "a personal machine has to be on" limit
  entirely. Rejected by the author on 2026-08-25 on `ago-business`'s `decisions/0001` criterion —
  spend where cost grows with use, not ahead of it — since there are no customers and a monthly bill
  would buy insurance against losing a demo. Two things worth carrying forward: a Russian-hosted
  bucket satisfies `personal-data.md`'s residency default while a US or EU one requires the legal
  question to be asked first; and when this is revisited, a managed *Postgres* service would cover
  Postgres only, leaving MinIO's attachments and Keycloak's database still needing this mechanism.
- **`restic` or `borg` to a remote repository.** Deduplication, encryption and retention as one tool,
  and genuinely better than a shell script at scale. Rejected: it needs installing on both ends, its
  repository format is a dependency a restore under pressure has to satisfy, and at 1 MB per day
  deduplication saves nothing. Reconsider when the artifact size makes whole-file copies wasteful —
  `15-05`'s measurements are the trigger.
- **A filesystem copy of the PVC directories instead of logical dumps.** Faster, and it needs no
  client for MinIO. Rejected for both stores: a Postgres data directory copied while the server is
  running is not a valid backup without WAL machinery this deployment does not have, and a MinIO
  directory copy bakes in the on-disk layout, so it can only be restored into the same MinIO release
  and can never be handed to a hosted S3.
- **WAL archiving / point-in-time recovery.** Put out of scope by `backlog/15-02` as a second node's
  worth of machinery for a one-node deployment. The measured restore numbers are what would justify
  revisiting it, not a preference stated in advance.
- **A symmetric passphrase (`gpg -c`, or `openssl enc`) instead of a keypair.** Simpler, and it needs
  no key management. Rejected because the passphrase would have to exist on the node for the scheduled
  run, which means the node can read its own backup history and the passphrase is a secret in a place
  that has no other secrets of its own.
- **Encrypting nothing, on the grounds that it is our own disk at both ends.** Rejected on the
  strength of what the artifact contains — every visitor's messages, a stranger's account, and role
  password hashes. `personal-data.md` names residency as a standing constraint precisely because of
  artifacts like this one, and "it is on our own disk" is the argument that stops being true the
  moment a disk is sold, a laptop is stolen, or a copy is made to move it.
- **A node-exporter textfile metric and a Prometheus alert rule for freshness**, instead of the mail
  watchdog. More uniform with `15-03`. Rejected as described in decision 6.
