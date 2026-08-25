# Backup, and a restore that has actually been performed

- **Stage**: 15
- **Status**: **done, 2026-08-25.** Backups run on a timer on the node and are collected off it; a
  restore was performed into an isolated scratch stack and the data was checked rather than assumed.
  `adr/0050` has the decisions, [`runbooks/backup-and-restore.md`](../runbooks/backup-and-restore.md)
  has the procedure and the drill's real numbers, and the outcome is summarised at the bottom of this
  file. One thing is left with the author and named there.
- **Depends on**: `15-01-keycloak-persistent-user-store.md` — a backup taken before Keycloak has a
  persistent store would be backing up two thirds of the system's real state and calling it a backup

## Goal

Every piece of durable state on the public deployment can be restored onto an empty cluster, and that
restore has been performed at least once rather than assumed. Today the deployment holds real tenant
data (`8-02`, `8-05`, and every account `10-01` lets a stranger create) on one node's local-path
volumes: `postgres-data` 2Gi, `minio-data` 2Gi, plus RabbitMQ and Redis. Nothing copies any of it off
that node. A lost disk is a lost product, and "it is only a demo" stopped being true the moment Stage
10 invited other people to put their own data in it.

## Context to read first

`deploy/k8s/base/postgres.yaml` and `minio.yaml` — the two PVCs that hold everything that cannot be
recreated from a manifest. `deploy/k8s/base/redis.yaml` and `rabbitmq.yaml` — deliberately different:
`architecture/realtime.md`'s degradation path already states Redis holds only ephemeral data and may
be lost, and RabbitMQ's durable state is recoverable by replay from the outbox (`architecture/
messaging.md`), so this item must decide per store whether it is backed up or explicitly declared
recreatable — with the reasoning, not by omission. `adr/0026` — the one-node, no-registry, images-built-
on-the-box reality any restore has to work within. `docs/runbooks/` — where the restore procedure lands.
`architecture/data-model.md`'s partitioning section — `messages` is partitioned, which a naive
`pg_dump`/`pg_restore` handles but is worth confirming rather than discovering during a real restore.

## The destination, decided 2026-08-25

**The author's own machine, pulled over the SSH access that already exists.** No paid service, no new
daemon, no new credential.

The reasoning, which is a constraint rather than a preference: there are no customers yet and no
revenue, so a monthly bill for object storage buys insurance against a loss that would currently cost
a demo. `ago-business`'s `decisions/0001` draws exactly this line — spend where cost grows with use,
not ahead of it. When there are real customers this is revisited, and a managed Postgres service is
the likely successor; note in advance that it would cover Postgres only, leaving MinIO's attachments
and Keycloak's database still needing this mechanism.

Two consequences follow, and both change what this item builds.

**The dump on the VPS is not the backup.** It is staging. The backup is the copy on a machine the VPS
cannot destroy, because the failure this exists for is losing the host — a dead disk, a suspended
account, a compromised root. A same-host copy covers only operator and software error. Real, worth
having, and not what the item is for.

**No SFTP server is needed.** SSH with the existing key already is one, and adding a daemon would
reopen surface the firewall closed on the same day (`17-05`). `rsync` over the existing channel does
the whole job with nothing new exposed.

## Scope

- A scheduled dump on the VPS — Postgres (logical dump is sufficient at this size; state why, and state
  the consistency guarantee it does and does not give), Keycloak's database (`15-01`), and the MinIO
  bucket contents — into a local staging directory, with rotation.
- **A scheduled pull from the author's machine**, over the existing SSH key. This is the step that
  makes it a backup; everything before it is preparation.
- **A freshness check.** This design's one weak point is that it depends on a machine being on and a
  scheduled task not having quietly failed — and silence looks exactly like success. Something must
  notice when the newest pulled copy is older than it should be. Cheap, and without it the whole
  arrangement is an assumption.
- **A retention window that also governs the pulled copies.** `16-02` and `adr/0031` define erasure as
  complete when the last backup holding the data has aged out. Copies sitting on a personal disk
  indefinitely make that statement false, so the local copies expire too, on the same window the
  privacy policy states. This is the point where "we deleted it" meets reality.
- Per store, an explicit line: backed up, or recreatable-and-why. Redis and RabbitMQ are expected to be
  the latter (`realtime.md`'s degradation path, and replay from the outbox); Postgres, Keycloak's
  database and MinIO the former.
- **A restore drill**: bring the whole stack up on an empty cluster from a pulled copy alone, and
  confirm a real conversation's history, a real attachment, and a real Keycloak login all survive.
  Written down, including how long it took — the only honest input to any future statement about
  recovery time.
- A runbook entry that a person who is not the author can follow under pressure.

## Out of scope

- Point-in-time recovery, WAL archiving, or a streaming replica — a second node's worth of machinery
  for a one-node deployment (`adr/0026`); the restore drill's measured numbers are what would justify
  revisiting this, not a preference stated in advance.
- Backing up Prometheus or Grafana volumes — metrics history is not product data, and `7-03` already
  reasons about Prometheus retention on its own terms.
- An RPO/RTO commitment. This deployment has no SLA (`architecture/nfr.md`'s "Availability behaviour"),
  and inventing one would be exactly the kind of number `CLAUDE.md` forbids. The drill measures what the
  restore actually costs; that measurement is the honest substitute.

## Done when

- [x] Backups of Postgres and MinIO run on a schedule and land off the node. `ago-backup.timer` daily
      at 02:30 UTC on the node; `backup-pull.sh` collects them onto the author's machine, and the
      collected copy is the backup.
- [x] Old backups are pruned by something, not by hand. Newest 7 runs on the node (verified live with
      `AGO_BACKUP_KEEP=2`: the oldest artifact **and** its checksum sidecar were removed); 30 days on
      the collected copies.
- [x] A full restore has been performed, with the elapsed time recorded. **14 s and 17 s** across two
      full runs, decryption through verified row counts; the second was run from scratch with the
      final committed scripts so the runbook describes the code that shipped. Deviation from the wording, stated rather than glossed: the target was an
      isolated three-container scratch stack (Postgres, MinIO, Keycloak) on the author's machine, not
      an empty *cluster*. What that does not exercise is bringing the workloads up, which is `15-06`'s
      subject and holds no state; what it does exercise is every store that does. The runbook's
      "Restoring onto a rebuilt node" section carries the six steps a real rebuild adds on top.
- [x] After that restore, a pre-existing conversation's history, a pre-existing attachment, and a login
      all work — checked, not assumed. All three, with real values in the runbook's drill table.
- [x] Every durable store is listed as backed-up or recreatable, with the reason. `adr/0050`
      decision 1 — including the two that needed an argument rather than a label, Redis and RabbitMQ.
- [x] The runbook exists and was the thing actually followed during the drill. It also records the
      three bugs the drill found in this item's own scripts, because a drill that finds nothing is
      usually a drill that was not really run.

## Open questions

None left in this item. Both it carried are answered: the destination is the author's own machine over
existing SSH (above), and the retention window is 30 days, set once and applied to the staging copies
and the pulled copies alike.

**One thing is the author's, and it is the load-bearing one** — see the outcome below.

## Outcome, 2026-08-25

Measured against the real deployment, not estimated: a backup run takes **4–5 s** and produces a
**1.08 MB** encrypted artifact; the pull takes **2 s**; the restore takes **14–17 s**. `15-05` wants
that size figure and nobody else was measuring it.

**The number worth carrying elsewhere**: `ago_chat.dump` is 1.05 MB of that 1.08 MB, and it is
dominated by `outbox` — **18 634 rows, which grew by about 14 000 in a single day**, against 17
messages in the same database. Nothing has ever deleted an outbox row (`personal-data.md`). Backup
size and disk growth on this node are an outbox-pruning story, not a conversation-history story, until
`15-04` exists.

**What is left with the author, and what is blocked on it.** The backup key currently in use was
generated by the session that built this, has **no passphrase**, and lives at
`~/.ago-backup/gnupg` on the author's machine; only its public half is on the node. Nothing is blocked
on replacing it — the mechanism is proven end to end with it — but three things are the author's and
only the author's:

1. **Put a passphrase on it.** One command, in the runbook. It costs nothing operationally, because
   nothing automated ever decrypts: the backup encrypts, the pull copies ciphertext, and only a human
   restoring ever types it. Existing artifacts stay readable; nothing has to be re-encrypted.
2. **Keep a copy of the private key off this machine.** Lose it and every artifact ever taken is
   permanently unreadable. There is no escrow. This is the single point of failure this design has.
3. **Schedule the pull.** The node's timer is enabled and running; the collection side was run by hand
   during the drill and is not yet on a schedule on the author's machine. Until it is, the node's
   watchdog will mail `alerts@` after 72 h — which is the design working, not a bug, but it is the one
   remaining manual step between "artifacts exist" and "there is a backup".

`17-03` should carry this key in its inventory.
