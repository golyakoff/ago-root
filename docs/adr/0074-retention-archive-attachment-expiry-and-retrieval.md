# ADR-0074: Retention archive — precise attachment expiry, and retrieval as a direct read

- **Status**: Accepted
- **Date**: 2026-08-29
- **Supersedes**: nothing. Extends `0031-retention-class-partitioning-and-archive.md`'s Decision 3/4
  (archive before drop; attachments follow their message's window), filling in mechanism `0031` itself
  left unspecified.

## Context

`13-06` built `adr/0031`'s shape: `messages` repartitioned by `(retention_class, created_at)`, an
archive written per (site, class, period) before a partition drops, and attachments expiring with
their messages. Two questions `0031` left open surfaced during implementation, both because the
physical shape turned out to have a wrinkle `0031`'s own prose did not anticipate:

1. **A site's messages for one calendar month can span two different retention classes.**
   `retention_class` is stamped once, at write time, from whatever tier was active then (`0031`
   Decision 2). A site that upgrades mid-month has some January messages under `free` and others under
   `starter` — two different partitions, two different drop schedules, both with `created_at` in
   January. `attachments` has no `retention_class` of its own. A naive expiry rule keyed on
   `(site_id, created_at range)` alone cannot tell these two partitions apart — the first one archived
   and dropped would delete attachments that in fact belong to messages still sitting in the *other*
   class's not-yet-archived partition: a straightforward false-positive data-loss bug hiding inside a
   design that reads as obviously correct until a tier change is considered.

2. **The archive already exists by the time anyone could ask for it.** `16-03`'s own tenant export is
   built on demand — a request row, a background job that packages a potentially slow export, a poll.
   This item's own backlog describes retrieval the same way. But `MessageArchiveJob` runs well ahead of
   any drop, unconditionally, for every site — there is no "on demand" step left by the time a tenant
   could plausibly ask, only a lookup.

## Decision

**1. Attachment expiry is keyed to the exact `attachment_id` set a partition's own rows reference,
captured immediately before that partition is dropped** (`MessagePartitionPruneQuery.
ListReferencedAttachmentIdsAsync`, read right before `DropPartitionAsync`, swept right after). Not a
`(site_id, created_at range)` predicate against the separate `attachments` table. This makes
"attachments follow their message's window" true by construction: an attachment can only be swept in
the same call that drops the one partition whose rows referenced it.

**2. Retrieval is a direct, permission-gated read — list, then a presigned download URL — not a
request/build/poll pipeline.** `ListMessageArchivesHandler`/`GetMessageArchiveDownloadUrlHandler` read
`message_archives` and mint a URL against the object `MessageArchiveJob` already wrote. A deliberate,
narrow departure from the backlog's own "same async job shape" wording: the *delivery mechanism* is
identical (a presigned URL, never a restore into the live product, matching `0031`'s own explicit
rejection of that) — only the *request* half is dropped, because nothing is left to enqueue by the
time a caller could ask.

**3. `MessageArchiveGate` refuses to confirm a partition while any of its rows still has a `NULL
site_id`.** A row `MessageSiteIdBackfillJob` (`18-01`) has not yet reached cannot be attributed to any
site's own archive; treating this as "not yet archived" turns an unresolved backfill into backpressure
on the drop rather than a silently lost row.

## Consequences

- `MessagePartitionPruneJob` gained an `IFileStorage` dependency and performs the attachment sweep
  itself, immediately after each drop, rather than a separately-scheduled job with its own cutoff logic
  to keep in sync.
- The retrieval endpoints have no POST counterpart and no `Pending`/`Ready`/`Failed` lifecycle to
  expose, unlike `16-03`'s export.
- `MessageArchiveJob` shares `MessagePartitionPruneJobOptions.RetentionHorizonMonths` rather than its
  own independently-configurable horizon, so the two jobs can never disagree about which partitions are
  candidates.
- A backfill that never converges would leave a partition undropped forever rather than drop it
  prematurely — the intentional failure direction (indefinite retention over silent data loss), but a
  real operational trap nothing pages on yet.
- Reading the live partition list itself needed a second fix, not directly about archiving but found
  while building it: `pg_inherits` filtered on `messages` stopped returning the monthly leaf partitions
  the moment `messages` gained a second partition level, returning only the three class-level parents
  instead — every consumer of `MessagePartitionPruneQuery.ListPartitionsAsync`
  (`MessagePartitionPruneJob`, `MessageSearchIndexJob`, `MessageSiteIdBackfillJob`) would have silently
  stopped finding anything to act on. Fixed by switching to `pg_partition_tree('messages') WHERE
  isleaf`, which returns the correct leaf set regardless of nesting depth — verified against a real
  Postgres 17. See `data-model.md`'s Partitioning section for where this is now documented as the
  standing fact.

## Alternatives considered

- **Attachment expiry by `(site_id, created_at range)`.** Simpler, matches `attachments`' own existing
  shape. Rejected: demonstrably wrong the first time a tenant changes tier mid-month.
- **Keep the request/poll shape for retrieval, purely for consistency with `16-03`.** Rejected: a
  request row and a job with nothing to build (the archive already exists) is machinery with no failure
  mode to protect against.
- **A separate, decoupled attachment-sweep job with its own cutoff.** Rejected: two independently
  scheduled cutoffs computed from the same clock and horizon are two places to keep in sync by hand, for
  no gain over doing the sweep as the direct next step after the one event that makes it safe.
