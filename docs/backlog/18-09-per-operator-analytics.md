# Per-operator analytics: the same numbers, broken down by who answered

- **Stage**: 18
- **Status**: done (`ago-chat#126`, `ago-console#63`, merged 2026-08-30)
- **Depends on**: `18-08-basic-operator-analytics.md` (done) — this item is the operator-filtered
  extension `18-08`'s own Out of scope section named as a real, deliberate follow-up rather than an
  afterthought

## Goal

A site owner can see, per operator, the same shape of numbers `18-08` already computes site-wide:
conversation count, average first-response time, and missed count — "how good is each operator", the
question `ago-business/docs/decisions/0009` names directly as something the nearest direct competitor
already reports and AGO does not.

## Why this, and why now

`18-08`'s own file: "Per-operator KPI ... a real, named follow-up (`0009` calls it out explicitly as
'the same derivation with an operator filter') ... not built here. This item proves the read shape
works before adding the second dimension." The read shape is now proven, live on the demo cluster; this
item adds the dimension it was scoped to add next.

## Context to read first

`18-08`'s own file in full — its "Definitions" section (first-response time, missed, per-channel
attribution) is the vocabulary this item extends, not redefines. `IOperatorAnalyticsReadStore`'s own
doc comment (`Ago.Chat.Infrastructure.Postgres`) — the query this item adds a `GROUP BY`/filter
dimension to, not a second query duplicating the same joins.

## What "quality," not just "activity," means here — decide before building

A raw count (conversations handled) measures activity, not quality, and conflating the two would make
the busiest operator look like the best one regardless of how they actually performed. This item's own
numbers — first-response time and missed rate, per operator — are genuine quality signals already
proven correct by `18-08`; **do not invent a new composite "quality score"** by combining them with
weights this project has no measured basis for (`CLAUDE.md` rule 7: no invented numbers). Report the
individual numbers side by side, let the site owner form their own judgment, the same "the numbers
exist and are readable, not a synthesized verdict" scope `18-08` already held itself to.

**What this item explicitly does not attempt**: a customer-satisfaction signal (a post-chat rating).
No such data is captured anywhere in this system today — building a rating feature is a real, separate
item (a new visitor-facing write path, a new personal-data row), not something this item's own SQL can
retrofit from data that does not exist. Name the gap plainly rather than approximating it from a proxy
that would misrepresent what it measures.

## Scope

- `IOperatorAnalyticsReadStore` (or a sibling port, decide which by how much the query actually
  diverges once written) gains an operator dimension: the same three numbers, grouped by
  `first_operator_id` per conversation (the operator who actually answered — not the currently
  assigned operator, which can differ after a `18-02` transfer; state explicitly which one this item
  uses and why).
- A console page or panel — extends `OperatorAnalyticsPage` with a per-operator table, or a new page
  linked from it; a plain table, no charting library, matching `18-08`'s own scope.
- Gated the same permission `18-08`'s own handler already uses (`site:configure`).

## Out of scope

- Any synthesized quality score or ranking — see above.
- Customer-satisfaction / CSAT data — does not exist in this system; naming the gap is this item's
  whole obligation on that front, not building a proxy for it.
- Historical data beyond `13-06`'s retention window, the same bound `18-08` already holds.

## Done when

- [x] Per-operator conversation count, first-response time, and missed count are computed correctly
      for a real site with real seeded data spanning multiple operators, proven by a test against real
      values, not by the query looking right.
- [x] A conversation transferred (`18-02`) between operators attributes correctly to whichever operator
      this item decided is "the" answering operator, proven by a test — the ambiguity named above,
      resolved and checked, not left implicit. Independently re-proven by the managing session: mutating
      `coalesce(first_operator_id, assigned_operator_id)` down to `assigned_operator_id` alone made the
      transfer-attribution test fail as expected.
- [x] Cross-site isolation is proven by a test, the same bar every read in this codebase holds.
- [x] A console panel renders the per-operator breakdown, gated by `site:configure`.

## Open questions

None left open by this item's own scope — the transfer-attribution question above is this item's to
decide and test, not to leave for a reader to guess.
