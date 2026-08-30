# Conversation duration report

- **Stage**: 18
- **Status**: ready
- **Depends on**: `18-08-basic-operator-analytics.md` (done) — the read-store and `GROUPING SETS`
  shape this item extends with one more aggregate column, not a new query

## Goal

A site owner can see how long a conversation typically takes from start to close — a standard support-
quality signal alongside `18-08`'s existing first-response time and missed-count numbers, and one every
comparable tool reports (`ago-business/docs/decisions/0009`'s own reporting-gap list). First-response
time answers "how fast did someone pick this up"; duration answers a different question — "how long
does it actually take to resolve," which matters on its own (a shop with a fast first response but a
long average duration has a different problem than one with a slow first response).

## Why this is the cheapest item in this round

Every timestamp this item needs already exists and is already written for other reasons:
`Conversation.CreatedAt` (non-nullable, set at `Start()`) and `Conversation.ClosedAt`
(`DateTimeOffset?`, set in `Close()`) are both already columns on `conversations`. No new write path, no
new domain concept, no migration, no widget change — the identical "derive it from data this system
already records" shape `18-08`'s own first-response-time and missed-count numbers already are, extended
with one more `avg(...)` expression in the same query.

## Scope

- Extend `OperatorAnalyticsReadStore`'s existing `SiteAnalyticsSql` with
  `avg(extract(epoch from (closed_at - created_at))) filter (where closed_at is not null)` as
  `AverageDurationSeconds`, computed inside the same `detail`/`GROUPING SETS` query `18-08`/`18-09`
  already run — not a second query, the same reasoning `18-09`'s own per-operator addition gives for why
  a third grouping set belongs in the existing pass over `detail` rather than a separately-filtered one.
- **A conversation with no `ClosedAt` (still open) contributes nothing to the average** — the same
  `filter (where ...)` discipline the existing `AverageFirstResponseSeconds` column already applies for
  its own "nothing to average yet" case, not a new pattern to invent.
- Surface the new column on every bucket the existing report already returns — overall, per-channel,
  per-operator — since the underlying query already computes all three in one pass; there is no cost to
  reporting it everywhere the query already reaches.
- Console: one more column on `OperatorAnalyticsPage.tsx`'s existing table(s), formatted with the same
  `formatDurationSeconds` helper `AverageFirstResponseSeconds` already uses — no new page, no new
  fetch, this rides the existing `OperatorAnalyticsResponse` payload with one more field.

## Out of scope

- A distribution (median, p90) rather than a mean — the existing first-response-time number is also a
  plain mean, and this item matches that shape rather than introducing a second statistical treatment
  for one column and not the other. A future item can revisit both together if a mean turns out to be
  too easily skewed by a handful of outlier long-running conversations.
- Any change to what "closed" means, or when `ClosedAt` gets set — this item reads an existing signal,
  it does not touch `18-06`'s auto-close behavior or `Close()`'s own semantics.

## Done when

- [ ] The report's `AverageDurationSeconds` field is correct against real seeded data spanning closed
      conversations with a known duration and at least one still-open conversation, proven by a test
      that specifically checks the open conversation is excluded from the average, not just that the
      closed ones average correctly.
- [ ] The number appears correctly in every bucket the existing report already returns (overall,
      per-channel, per-operator), proven by a test.
- [ ] Cross-site isolation is proven by a test (already covered by the existing suite for this
      read-store — confirm the new column does not weaken that, don't re-derive it from scratch).

## Open questions

None. This item has no undecided design question — it is a mechanical extension of an existing,
already-decided query shape.
