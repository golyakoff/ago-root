# 25-72 · Two worker replicas can claim the same export

- **Stage**: 25
- **Status**: done — `ago-chat#277`/`ago-console#216`
- **Found**: 2026-09-13, discussing `16-03`'s export queue's own failover story with the author.
  Not a live bug today — `Ago.Chat.Worker` runs one replica — named so it is not discovered by
  running a second one for real availability and finding two replicas silently doubling every export.

## What is actually true today

`SiteExportQuery.ListPendingAsync` (`Ago.Chat.Worker`) is a plain `SELECT ... WHERE status = 'Pending'
ORDER BY requested_at LIMIT @limit` — no `FOR UPDATE SKIP LOCKED`, no atomic transition to an
in-progress status. `SiteExportJob.SweepAsync` reads a batch, then processes each item in a loop; only
`ProcessExportAsync`'s own final step marks a request `Ready` (or the caller marks it `Failed`).

Two `Ago.Chat.Worker` replicas ticking at close enough times would both read the same `Pending` row in
the same window and both build and upload the same tenant's archive — wasted work, and whichever
`MarkReadyAsync` lands second silently overwrites the first's `object_key`, orphaning the first upload
in storage with nothing ever pointing at it.

## Scope

- Claim a batch atomically before processing it — either `FOR UPDATE SKIP LOCKED` inside the same
  transaction that reads the batch, or an explicit `UPDATE export_requests SET status = 'Processing'
  WHERE status = 'Pending' ... RETURNING id, site_id` compare-and-set, matching whichever idiom this
  codebase's other claim-then-process jobs already use (check `SiteErasureJob`'s own claim query
  first — same shape, same product, likely already solved once).
- A `Processing` request that never completes (a crashed worker mid-build) must not stay stuck forever
  — either a stale-claim sweep-back-to-`Pending` after a timeout, or accept operator-triggered retry as
  the recovery path; state which and why.

## Done when

- [x] Two `SiteExportJob` instances ticking concurrently against the same database claim disjoint
      batches — proven by actually running two instances against one database, not by reading the
      query.

## Answered, 2026-09-13

`SiteExportClaimQuery.ClaimPendingBatchAsync` (`Ago.Chat.Worker`) replaces the plain read with a single
`UPDATE export_requests SET status = 'Processing', processing_started_at = @now WHERE id IN (SELECT ...
FOR UPDATE SKIP LOCKED) RETURNING id, site_id` — the same claim-then-resolve shape
`SiteExportPruneQuery.ClaimExpiredReadyBatchAsync` (`25-75`) already established, deliberately simpler
here since no pre-update column value is needed. `MarkReadyAsync`/`MarkFailedAsync` now resolve from
`Processing`, not `Pending`. A crashed replica's abandoned claim is recovered by
`SiteExportClaimQuery.ReclaimStaleBatchAsync`, called at the top of every `SweepAsync` cycle once a row
has sat `Processing` longer than `SiteExportJobOptions.StaleProcessingTimeout` (1 hour — an internal
robustness constant, reasoned but not measured) — the stale-sweep-back-to-`Pending` option this item's
own Scope named, not operator-triggered retry.

Proven with `Ago.Chat.Concurrency.Tests.SiteExportClaimConcurrencyTests` (9 tests, its own isolated
Postgres container): several concurrent claim calls against one real database, each simulating a
`Worker` replica, claim disjoint batches covering every seeded row exactly once. Fails-before confirmed
by temporarily removing `FOR UPDATE SKIP LOCKED`: the covering/disjoint assertion then failed 5 of 6
runs with duplicate claims across callers.

Console side (`ago-console#216`): `SiteExportPage.tsx`'s `statusLabel` switch is deliberately
exhaustive-checked (no `default` case) over the closed `SiteExportStatus` union, so the new `Processing`
value had to be added there too or the console would stop compiling once this shipped — not merely a
cosmetic follow-on.
