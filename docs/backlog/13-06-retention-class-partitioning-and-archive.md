# Retention class: repartition `messages`, prune per class, archive before dropping

- **Stage**: 13
- **Status**: ready — the shape is decided (`adr/0031`, 2026-08-25); the window's length is a
  measurement `15-05` supplies, and the operational default from `15-04` holds until it does, so this
  item can be built and switched on without it
- **Depends on**: `15-04-retention-and-pruning-jobs.md` (the bounded-batch and partition-drop machinery
  this reuses rather than duplicates), `16-03-tenant-data-export.md` (its export format is the
  archive's format — whichever lands first defines it), and `15-05-capacity-and-disk-headroom.md` for
  the number, not for the mechanism

## Goal

Conversation history stops growing forever, differently per tier, without the expensive path. After
this item `messages` is partitioned by an immutable retention class and then by month, expired
periods are archived as one file per site per period and then dropped as a partition, and attachments
expire with the messages they belong to.

## Context to read first

`adr/0031` in full — the decision, and specifically why the partition key carries a retention *class*
stamped at write time rather than the tenant's current tier. That distinction is the whole item; a
session that implements "partition by tier" instead will produce something that rewrites a customer's
entire history the first time they pay. `adr/0019` — the unique-index widening this repeats once
more, and the argument for why it is acceptable. `architecture/data-model.md`'s partitioning section
and `PartitionMaintenanceJob` — the existing monthly mechanism, which grows a dimension rather than
being replaced. `ago-business/docs/decisions/0001` — the cost criterion this satisfies.
`architecture/personal-data.md` — why the archive is a new store with obligations attached, not just
a cheaper disk.

## Scope

- **The migration.** `messages` becomes multi-level: `PARTITION BY LIST (retention_class)`, each class
  itself `PARTITION BY RANGE (created_at)` monthly. Postgres cannot convert in place — `2-06` already
  hit this and its migration is the worked precedent (rename, create the replacement, copy, drop),
  including why it is marked one-way. Existing rows get the class their site's current tier maps to;
  state that this is a one-time approximation, since nothing records what tier a historical message was
  written under.
- **`retention_class` on `messages`**, written by the message pipeline from the site's tier at write
  time and never updated afterwards. Where it is resolved matters: it must not become a per-message
  lookup of billing state on the hot path — cache it with the site config that `3-04` already caches,
  and treat a stale value as acceptable (it is a stamp, not a gate, `adr/0031`'s own note on rule 8).
- **Widen the keys** per `adr/0019`'s established consequence, and update that ADR's own text to point
  here rather than leaving it describing a narrower key than the schema has.
- **`PartitionMaintenanceJob` creates per class per month** — same idempotent
  `CREATE TABLE IF NOT EXISTS ... PARTITION OF` shape, one more dimension.
- **The archive step, before any drop.** One object per site per period, in `16-03`'s export format,
  written to object storage under its own prefix and storage class. Nothing is dropped until its
  archive is confirmed written — a partition drop after a failed archive upload is unrecoverable data
  loss, and this ordering is the only thing preventing it.
- **Attachment expiry follows the message**, including the thumbnail — reuse `5-04`'s sweeper rather
  than writing a second deletion path.
- **Retrieval**: a tenant can request an archived period and receive the file. Same async job shape
  and same delivery mechanism as `16-03`'s export; not a restore into the live product
  (`adr/0031` rejects that explicitly and says why).
- **Verified against data actually past the window**, including a real archive write, a real partition
  drop, and a real retrieval — not against an empty table.

## Out of scope

- **The window's length.** `15-05` measures; `13-05` records the resulting per-tier numbers. This item
  reads them as configuration and works with whatever `15-04`'s operational default is until then.
- Restoring an archive into the live product — `adr/0031`, rejected with reasons.
- The console surface for tiers and upgrades — `13-04`.
- Erasure on request — `16-02`, which this item makes strictly harder by adding a store it must reach;
  that is recorded there rather than solved here.
- Choosing the archive's storage class provider — constrained by `16-01`'s residency rule and by
  `adr/0031`'s requirement that it permit deletion, and otherwise the same open vendor question
  `15-02` already carries.

## Done when

- [ ] `messages` is partitioned by class then month, with the migration applied to a real Postgres
      from scratch and the keys widened per `adr/0019`.
- [ ] `retention_class` is stamped at write time and provably never updated afterwards — including a
      test that changing a site's tier leaves existing rows untouched.
- [ ] `PartitionMaintenanceJob` maintains the full grid idempotently.
- [ ] A period is archived to object storage and only then dropped, proven by a test where the archive
      write fails and the drop does not happen.
- [ ] Attachments and thumbnails for an expired period are gone.
- [ ] A tenant can request and receive an archived period.
- [ ] `adr/0019`, `data-model.md` and `personal-data.md` all describe the schema and stores as they
      now are.

## Open questions

None. The one number this needs has a named source and a stated interim default.
