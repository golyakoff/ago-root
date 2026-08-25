# Backup, and a restore that has actually been performed

- **Stage**: 15
- **Status**: ready — the destination was decided 2026-08-25 (author's call, recorded below), so this
  item is no longer parked on anything
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

- [ ] Backups of Postgres and MinIO run on a schedule and land off the node.
- [ ] Old backups are pruned by something, not by hand.
- [ ] A full restore onto an empty cluster has been performed, with the elapsed time recorded.
- [ ] After that restore, a pre-existing conversation's history, a pre-existing attachment, and a login
      all work — checked, not assumed.
- [ ] Every durable store is listed as backed-up or recreatable, with the reason.
- [ ] The runbook exists and was the thing actually followed during the drill.

## Open questions

None. Both questions this item carried are answered: the destination is the author's own machine over
existing SSH (above), and the retention window is whatever the privacy policy states — set once,
applied to the staging copies and the pulled copies alike, rather than chosen twice.
