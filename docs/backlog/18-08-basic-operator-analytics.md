# Basic operator/site analytics

- **Stage**: 18 — placed here for lack of a better-fitting stage; this is site-owner-facing operational
  visibility, not strictly "operator does the obvious thing faster" the way `18-01`-`18-07` are, but it
  lives in the console the same way they do and needs no new architectural surface. Revisit placement if
  a future session finds a stage that fits it better; not worth inventing a new stage for one item.
- **Status**: done (2026-08-29, `ago-chat#123` + `ago-console#61`) — see Outcome below
- **Depends on**: nothing new architecturally — reads existing data through a new Dapper read store, the
  same access-strategy shape every other console read already uses

## Goal

A site owner or operator can see, without leaving the console: how many conversations came in, average
first-response time, and how many messages went unanswered, per channel, over a real time window — the
most basic "how am I doing" visibility a support tool owes its own user, which this product does not
have at all today.

## Why this, and why now

`ago-business/decisions/0009` names this as "Level
2" of the gap against the nearest direct competitor — cheap to build (no new write path, purely
derived from data already recorded) and, unlike CRM depth or telephony (also named in that document,
and explicitly rejected), genuinely wanted by the target customer independent of what any competitor
offers: a small shop owner wants to know how their own support is doing, not to match a feature list.

**This is explicitly not `12-02`.** `12-02`'s cross-tenant read API is for the platform owner (AGO's
own team) to see usage signals across every tenant at once, gated by `RequirePlatformOwner`. This item
is the mirror image: one tenant's own owner/operator, seeing only their own site's numbers, through the
ordinary `conversation:read`/`site:configure`-shaped permission a ordinary console user already holds.
No cross-tenant read is introduced by this item.

## Context to read first

`docs/architecture/data-model.md`'s "Access strategy" section — reads go through Dapper read stores,
this is another one, not a new pattern. `messages`/`conversations`' own columns (`created_at`,
`delivered_at?`, `read_at?`, `author_kind`) already carry everything a first-response-time and
missed-message calculation needs; verify this before assuming any new column is required — the working
assumption going in is that none is.

## Scope

- A new read store (or an extension of an existing one) answering, scoped by `site_id` and a caller-
  supplied date range: conversation count, average time from the first visitor message to the first
  operator reply, count of conversations that never received an operator reply within the window, and
  a per-channel breakdown of the above (`ChannelKind` already exists as the dimension to group by).
- A console page or panel surfacing this — a plain table/summary, not a charting library; this item is
  about the numbers existing and being readable, not about visualization polish.
- Gated the same way `GetAllConversationsForSiteHandler` already is (`site:configure` or
  `conversation:read` — decide which is the better fit and record why, the same discipline every other
  new handler in this codebase already holds itself to).

## Out of scope

- Per-operator KPI (response speed, activity, broken down by individual operator rather than the whole
  site) — a real, named follow-up (`0009` calls it out explicitly as "the same derivation with an
  operator filter"), not built here. This item proves the read shape works before adding the second
  dimension.
- Any chart/graph rendering library — numbers in a table are the whole of this item's Done-when.
- Historical data beyond what `13-06`'s retention window already keeps live — this item reads the same
  live window every other console feature does, no special exemption from retention.

## Done when

- [x] A real conversation volume, average first-response time, and missed-conversation count are
      computed correctly for a real site with real seeded data, proven by a test against real values,
      not by the query looking right.
- [x] The same three numbers are broken down per channel.
- [x] A console panel/page renders them, gated by the permission this item's own scope decides on.
- [x] Cross-site isolation is proven by a test — a caller cannot see another site's numbers through
      this endpoint, the same bar `17-01`'s own tenant-isolation discipline holds every new read to.

## Open questions

None left open — see Outcome below.

## Outcome

`OperatorAnalyticsReadStore` (`Ago.Chat.Infrastructure.Postgres`) answers the whole shape in one query:
`GROUPING SETS ((), (channel_label))` computes the site-wide total and every channel's bucket in one
pass over a `detail` CTE built from two `LEFT JOIN LATERAL ... ON TRUE`s — one resolving the visitor's
earliest-linked `channel_identities` row (widget visitors get the literal label `"Widget"`, since
`ChannelKind` deliberately has no `Widget` member), the other resolving each conversation's first
visitor/first operator message timestamps. `ON TRUE` is load-bearing: without it a conversation with no
channel identity or no messages yet would drop out of the result instead of producing an honest zero
row. First-response time is an average over conversations that *did* get an operator reply — a
conversation with none is excluded from that average, not counted as zero. Missed = `Closed` state with
no operator reply at all. A site with zero conversations in the window returns zero rows (Postgres's
`GROUPING SETS` has nothing to group), which `GetSiteAnalyticsAsync` turns into an explicit zero bucket
rather than an empty response the caller would have to special-case.

`GetOperatorAnalyticsForSiteHandler` gates on `Permission.SiteConfigure` (chosen over
`conversation:read`: this is site-level operational visibility, the same tier as the site's other
configuration reads, not a conversation-content read). Console: `OperatorAnalyticsPage.tsx`, a plain
summary table, no charting library, matching the item's own scope.

**Tenant isolation independently re-verified by the managing session**, not just accepted from the
worker's report: mutated `where c.site_id = @SiteId` to `where (c.site_id = @SiteId or true)` in the
read store's SQL, confirmed 4 tests then failed with real cross-site leakage in their assertions,
reverted, re-ran the full suite green twice.

One real complication surfaced during the build: `13-06`'s same-day repartitioning of `messages` by
retention class (`Stage13RepartitionMessagesByRetentionClass`) broke the naive test-seeding helper this
item's tests first used (Postgres `42P16`, inserting into a partitioned parent without routing) — fixed
by seeding through the correct partition via `MessagePartitionNames`, the same helper `13-06`'s own
tests already established as the pattern.
