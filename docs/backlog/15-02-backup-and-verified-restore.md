# Backup, and a restore that has actually been performed

- **Stage**: 15
- **Status**: ready — scoped so the one real cost decision (the off-node backup destination, Open
  questions below) is named rather than invented, exactly as `14-03`/`20-05` handle their own vendor
  choices; everything else in this item can be built before it is answered
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

## Scope

- A scheduled backup of Postgres (logical dump is sufficient at this size; state why, and state the
  consistency guarantee it does and does not give) and of the MinIO bucket contents.
- Copies land **off the node** — a lost VPS disk must not also lose the backups. The destination is a
  real choice with a real cost (object storage at the same or another provider); name it, price it, and
  do not invent a number for either.
- Retention and rotation for the backups themselves — how many, how far back, and what deletes the old
  ones. Backups that grow forever fill the same 2Gi-class disk they are protecting.
- Per store, an explicit line: backed up, or recreatable-and-why. Redis and RabbitMQ are expected to be
  the latter; Keycloak's database (`15-01`) and Postgres and MinIO are expected to be the former.
- **A restore drill**: bring the whole stack up on an empty cluster from backup alone, and confirm a
  real conversation's history, a real attachment, and a real Keycloak login all survive. The result is
  written down — including how long it took, which is the only honest input to any future statement
  about recovery time.
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

- **Where the off-node copies live.** A real choice with a real monthly cost, and the author's to make
  — the same class of decision `adr/0026` made for the host itself. This item can be started on
  everything else; the destination must be settled before the first scheduled backup is switched on.
