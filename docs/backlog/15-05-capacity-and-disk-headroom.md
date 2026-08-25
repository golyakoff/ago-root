# Capacity: what happens as the one node fills up

- **Stage**: 15
- **Status**: ready
- **Depends on**: `15-04-retention-and-pruning-jobs.md` — sizing a volume against a table that grows
  forever answers the wrong question; prune first, then size what is left

## Goal

The deployment's real capacity limits are known, sized deliberately, and fail in a way that has been
observed rather than imagined. Today the PVCs carry the sizes a local Docker Desktop cluster was given
— Postgres 2Gi, MinIO 2Gi, RabbitMQ 1Gi, Prometheus 1Gi, Redis 512Mi, Grafana 512Mi — inherited
unchanged by the public deployment through `overlays/demo`, which patches images, hostnames and TLS but
never storage. They all sit on one node's local-path provisioner, which means they share one disk:
whichever component fills it takes the others down with it, and Postgres in particular does not
degrade gracefully when it cannot write.

## Measured 2026-08-25, and it overturns this item's own premise

Taken on the live node, so these replace the estimates this item was written against.

| Volume | Requested in the PVC | Actually used |
|---|---|---|
| `postgres-data` | 2Gi | 85M |
| `prometheus-data` | 1Gi | 20M |
| `grafana-data` | 512Mi | 15M |
| `rabbitmq-data` | 1Gi | 10M |
| `minio-data` | 2Gi | 100K |
| `redis-data` | 512Mi | 8K |

Node disk: **79G total, 15G used, 60G free.** Everything above adds up to about 130M.

**The requested sizes are not enforced.** The storage class is `local-path`, which backs a volume with
a directory on the node's own filesystem and does not apply a quota. Postgres inside its pod reports
`78.6G total, 59.7G free` for its data directory — the node's root filesystem, not a 2Gi volume.

That matters more than the numbers, because several items reason from a ceiling that does not exist:

- This item's own scope said to "resize deliberately where the inherited local-dev number is wrong".
  Resizing changes nothing while the class ignores the value; the question is headroom on the node,
  and whether a real quota is wanted at all.
- `5-13` describes a stranger writing unbounded bytes "to a shared 2Gi volume". They would write to
  the node's shared 60G — less urgent by volume, worse in kind, since filling it takes down every
  component at once rather than one.
- `15-04`'s operational default and `adr/0031`'s retention window were both framed as "sized to keep a
  2Gi volume alive". The number they need comes from the node's free space and its growth rate.

Correcting those three is part of this item's work, not a separate cleanup.

## Context to read first

`deploy/k8s/base/*.yaml`'s PVC declarations — the six sizes above, and the fact that `overlays/demo`
overrides none of them. `adr/0026` — one node, local-path storage, chosen deliberately; this item works
within that decision rather than reopening it. `docs/runbooks/k8s-local.md`'s "Known limits of this
setup" — the local limits `8-01` said the public deployment inherits; this item states which of them
now actually bite. `docs/backlog/5-13-fix-presigned-upload-size-not-enforced-by-s3.md` — the same
investigation that produced this concern (disk-exhaustion exposure of the public demo, 2026-08-24) and
the one path by which a stranger can currently write an unbounded number of bytes to that shared disk.
`architecture/file-storage.md`'s quota discussion. `architecture/realtime.md`'s degradation path — what
is *supposed* to happen when a dependency is unavailable, which is the benchmark for what actually
happens when the disk is full.

## Scope

- Measure current real usage per volume on the live deployment, and the node's total disk. Not an
  estimate — the numbers, in the item's own write-up.
- Resize deliberately where the inherited local-dev number is wrong for a public deployment, and record
  why each final number was chosen. Note that local-path PVC expansion on k3s is not always in-place;
  find out what it costs here before needing it in a hurry.
- Reserve headroom the cluster itself needs (container images, k3s state, logs, `15-02`'s local staging
  copies before they are shipped off-node) — a volume sum equal to the disk is a full disk.
- **Observe the failure.** Fill a volume on purpose, in a throwaway environment, and write down what
  actually happens: which component fails first, whether Postgres recovers on its own once space is
  freed, whether the API returns errors or hangs, and whether anything corrupts. Everything else in this
  item is guesswork without it.
- Feed the resulting thresholds into `15-03`'s disk rules — alert with enough margin to act, derived
  from the measured fill rate rather than from a round percentage.
- State the per-tenant exposure plainly: with `10-01`'s self-registration live, the number of accounts
  that can be created is unbounded, and each one can upload attachments. Whether that is contained by
  `5-13`'s enforced upload ceiling, by `13-05`'s storage caps, or by a deliberate limit on open
  registration is named here and decided in those items — but the exposure is written down here, not
  left implicit.

## Out of scope

- Moving to a multi-node cluster, external managed Postgres, or external object storage — `adr/0026`'s
  decision, revisited only with real numbers this item might one day produce, not as part of it.
- Autoscaling of any kind (`8-01` already ruled it out for this deployment).
- Application-level storage quotas per tenant — `13-05`'s entitlement work, which this item informs.

## Done when

- [ ] Measured usage per volume and total node disk are recorded, with the date.
- [ ] Every PVC size on the demo overlay is either deliberately chosen or deliberately confirmed as
      inherited, with the reason.
- [ ] The sum of volumes plus reserved headroom is below the node's disk, shown arithmetically.
- [ ] A deliberate disk-full test has been run and its observed behaviour written down.
- [ ] `15-03` has disk alert thresholds derived from those observations.
- [ ] `runbooks/k8s-local.md`'s limits section and `8-01`'s inherited-limits claim are updated to match
      what is now known.

## Open questions

None. Every decision here is one a session can make from measurements it takes itself.
