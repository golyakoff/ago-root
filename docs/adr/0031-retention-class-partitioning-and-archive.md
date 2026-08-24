# 0031 — History retention: an immutable retention class in the partition key, and an archive instead of deletion

- **Status**: Accepted
- **Date**: 2026-08-25
- **Supersedes**: nothing. **Extends** `0019-partitioned-messages-widens-the-unique-index.md`, whose
  consequence this decision widens by one column and whose reasoning it reuses rather than reopens.

## Context

`backlog/13-05` has been blocked since it was written on one unanswered question: does the free tier
get a bounded history window, or is history unlimited regardless of tier? Nothing in either
repository decided it, and the item refused to default on it — deleting a real customer's real
conversation history on a wrong guess is not a reversible mistake the way a mistuned rate-limit
bucket is.

Three separate things had been sharing that one question, and separating them is most of the answer:

1. **Operational pruning** — outbox rows, the webhook delivery log, old partitions. Not
   customer-visible, already scoped as a mechanism in `15-04`, never in dispute.
2. **Product retention of conversation history** — a candidate tier lever, which is what `13-05` asked
   about.
3. **A ceiling on how long personal data is held at all** — surfaced by `architecture/personal-data.md`
   (2026-08-25), which found that message content is the bulk of the personal data in this system and
   the one part that cannot be minimised by choosing fields. Retention is the only lever on it. Nobody
   had framed this before, and it applies regardless of what a tenant pays.

The technical constraint that shaped the decision: `messages` is already
`PARTITION BY RANGE (created_at)`, monthly (`2-06`), chosen precisely because `DROP PARTITION` makes
retention cheap. But partitions are shared across every tenant, so a tier-differentiated window
cannot use them: dropping a month deletes it for paying tenants too. Naive tier differentiation
therefore forces bounded-batch row deletes filtered by site — the expensive path partitioning existed
to avoid — and the partition can only be dropped once the *longest* tier's window has passed, so most
of the storage saving evaporates as well.

`ago-business`'s own `decisions/0001` supplies the criterion this has to satisfy: the free/paid line
is drawn by whether a feature's cost grows with usage. Stored history does grow, monotonically and
forever, so unlimited history on a free tier fails that criterion on its own terms.

## Decision

**1. `messages` is partitioned by an immutable retention class, then by month.** Multi-level
partitioning: `PARTITION BY LIST (retention_class)` at the top, each of which is itself
`PARTITION BY RANGE (created_at)` monthly, exactly as today. Dropping "free tier, older than the
window" becomes one `DROP PARTITION` again, and a tier-differentiated window costs no more than a
uniform one.

**2. The retention class is derived from the tenant's tier when the message is written, and never
changes afterwards.** This is the load-bearing half of the decision. Partitioning by the tier itself
would mean that changing tier moves rows between partitions — a mass rewrite of a tenant's entire
history, landing at the exact moment a customer first pays, and on downgrade silently making a paying
customer's history eligible for deletion. An immutable class removes both: an upgrade changes where
*future* messages land and moves nothing, and a downgrade destroys nothing.

The product-facing statement is correspondingly simple and honest: **history is kept according to the
plan it was written under.** Upgrading lengthens the future, it does not buy back the past.

**3. Expired history is archived, not deleted.** At prune time, one archive object per site per period
is written in `16-03`'s tenant-export format, to the same object storage under a distinct prefix and
storage class, before the partition is dropped. Retrieval is a request the tenant makes and a file
they receive — not a restore into the live product.

**4. Attachments follow their message's window.** A file expires with the conversation it belongs to.

**5. The window's actual length is not set here.** It is set once `15-05` has measured real storage
growth per tenant, which nobody has done. `15-04`'s operational default holds until then, and
`CLAUDE.md`'s prohibition on inventing numbers is the reason this ADR names a shape and not a figure.

## Consequences

- **`0019`'s widening happens once more.** Every unique constraint on a partitioned table must include
  the partition key, so the primary key becomes `(id, created_at, retention_class)` and the
  `(conversation_id, sequence, created_at)` index widens correspondingly. `0019` already argued why
  this is acceptable — the index is the last line of defence, not the first, which remains the
  `Conversation` aggregate's optimistic-concurrency check on `xmin` — and that argument carries over
  unchanged. It is a further weakening of the same backstop, not a new kind of risk.
- **`messages` gains a `retention_class` column**, denormalised from the tenant's tier at write time.
  It is not a cache of anything a write decision depends on (`CLAUDE.md` rule 8): nothing reads it to
  decide whether a write may proceed. It is a stamp of what was true when the row was created.
- **`PartitionMaintenanceJob` creates partitions per class per month**, multiplying the partition
  count by the number of classes. With three tiers and a two-year horizon this is tens of partitions,
  not thousands.
- **Queries that do not filter by class cannot prune partitions.** Most reads filter by
  `conversation_id`, which does not identify a class, so they scan every class branch. The bounded
  index size that motivated `2-06` is diluted by the number of classes — acceptable at three, and a
  reason not to invent more classes than there are tiers.
- **The archive is a new store of personal data.** `personal-data.md`'s table gains a row, `16-02`'s
  erasure must reach it, and it is subject to `16-01`'s residency constraint. Archiving moves the
  liability, it does not end it, and the published policy has to say that plainly rather than implying
  expired history is gone.
- **The archive's storage class must permit deletion on request.** Cheap cold tiers are frequently
  immutable or carry a minimum billable retention; either would make `16-02` undeliverable. This is a
  selection constraint, not a preference.
- **`16-03`'s export format becomes load-bearing twice over.** It is the tenant's own export and the
  archive's on-disk shape. A change to it is a change to both, and the archive's existing copies were
  written in the old one.
- **`13-05` is partly unblocked**: the shape of the retention answer is decided here, and the number
  it still needs is now a measurement rather than an open product question.

## Alternatives considered

- **A uniform window for every tier.** The cheapest possible answer — a plain `DROP PARTITION` with no
  new column, no key widening, no multi-level partitioning — and it delivers the privacy ceiling on
  its own. Rejected because it removes history as a tier lever entirely, leaving `0001`'s
  cost-containment criterion to be satisfied by attachments and seats alone.
- **Partitioning by the mutable tier.** The obvious reading of the same idea, and the reason the
  immutable class exists: see Decision 2.
- **A message-count cap instead of a time window.** Does not align with range partitioning at all — it
  is per-conversation row deletion by construction — and leaves storage unbounded in time for a
  low-volume tenant, which is the case the cost criterion is actually about.
- **Deleting outright, with no archive.** Simplest, and it genuinely ends the data liability rather
  than relocating it. Rejected by the author: losing a customer's history irrecoverably is a worse
  product than one that can produce it slowly on request.
- **Restoring an archive back into the live product.** Rejected as disproportionate: it requires
  rebuilding `sequence` continuity, landing rows in the right partitions, recomputing unread counters
  and reconciling with conversations that have moved on since — a large amount of machinery for a rare
  need that handing over a file already serves.
