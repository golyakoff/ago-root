# ADR-0103: A rate carries its own fraction, a figure carries its own preceding period, and a thin sample never ranks

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 23

## Context

`docs/design/decisions.md` §7 was amended on 2026-09-04: refusing to print a rate built on a thin
sample was reversed in favour of showing it in full, alongside its own numerator and denominator -
"50% (1 of 2)" is honest; a silent refusal hides information the reader could judge themselves. The
threshold survives for one purpose only: ranking. Operators, and any other row a report compares
against its peers, must never be sorted by a rate whose own denominator is too small to mean
anything - the amendment's own words are "the threshold ranks, it does not silence".

`23-16` implements that amendment against the four analytics reports (`/analytics`,
`/analytics/conversion`, `/analytics/tags`, `/analytics/booking-flow`) and adds the second half of
decisions.md §7's rule this codebase had not yet built: "a figure carries the preceding period to
compare it against... dynamics, relative and absolute together." Two genuinely separate design
questions came out of that work, both worth recording because an obvious-looking alternative existed
for each and was rejected for a specific reason.

## Decision

### 1. The preceding-period comparison is computed by calling each report's existing single-window
   read-store method twice from its handler - never a second read-store method, never new SQL

Each of the four handlers (`GetOperatorAnalyticsForSiteHandler`, `GetConversionReportForSiteHandler`,
`GetTagBreakdownReportForSiteHandler`, `GetModuleFlowReportForSiteHandler`) already took a `from`/`to`
window and called one read-store method once. `23-16` adds a second call, for the immediately
preceding window of equal length, computed by a single shared helper -
`Ago.Chat.Application.Abstractions.PrecedingPeriod.Before(from, to)` returns
`(from - (to - from), from)`. Both calls are issued before either is awaited
(`Task.WhenAll`), so they run concurrently rather than doubling the handler's own latency, and the
response DTO carries both periods' figures in one payload.

```csharp
var (previousFrom, previousTo) = PrecedingPeriod.Before(from, to);
var currentTask = readStore.GetConversionReportAsync(query.SiteId, from, to, cancellationToken);
var previousTask = readStore.GetConversionReportAsync(query.SiteId, previousFrom, previousTo, cancellationToken);
await Task.WhenAll(currentTask, previousTask);
```

No read-store interface changed. The port's own contract - "give me this site's numbers for this
window" - already says everything a caller comparing two windows needs; what changed is a policy
decision in the Application layer about *which* two windows to ask for and how to combine the
answers, which is exactly where a policy belongs under the dependency rule (`clean-architecture.md`):
`Infrastructure.Postgres` stays a plain single-window projection, and the comparison rule lives in
`Ago.Chat.Application` where every other cross-cutting analytics decision in this codebase already
does (`IOperatorAnalyticsReadStore`'s own remarks call this "the port takes the resulting timestamp,
not a policy").

### 2. `AnalyticsOptions.MinimumSampleForRate` is consumed inside the two read stores that actually
   rank on a rate, and nowhere else

`ConversionReportReadStore.byOperator` and `TagBreakdownReadStore.byTag` are the only two lists in
this codebase's four analytics reports that carry a genuine rate a reader could use to compare rows
against each other. Both now order their rows in two tiers: rows whose own `RecordedCount` meets
`MinimumSampleForRate` sort first, ranked by their own rate descending; every other row follows,
ranked by an absolute (`RecordedCount` / `ConversationCount`) instead - never by the rate a thin
sample cannot support. A final tie-break by id/name makes the order fully deterministic rather than
resting on whatever order Postgres happens to return equal keys in.

`OperatorAnalyticsReadStore`'s four `By*` lists and `ModuleFlowReadStore`'s single row take no
dependency on `AnalyticsOptions` at all: neither report renders a rate with a denominator a thin
sample could distort (durations and counts are real numbers about whatever they were computed from,
not fractions that misrepresent a population), so there is no ranking hazard for the threshold to
guard, and their existing alphabetical/id order already satisfies "a stable, stated order" for a
report that does not rank.

## Consequences

**Positive.** The comparison feature cost no EF migration, no new SQL, and no new read-store
interface method - four handlers each grew a few lines of orchestration and one shared helper. The
ranking threshold is real, testable business policy (`ConversionReportReadStoreTests.
GetConversionReportAsync_NeverRanksAThinSampleAboveARealRate_EvenWhenItsOwnRateIsHigher` and its
`TagBreakdownReadStoreTests` sibling prove it against a real Postgres query, not merely a Fake), and
it is configuration (`Analytics:MinimumSampleForRate`, default 10, validated at startup like every
sibling options class), not a constant buried in a comparison expression - the amendment's own
"configuration, not a constant" requirement.

**Negative.** Each of the four analytics endpoints now issues two database round trips instead of
one, per request. At the volumes `IOperatorAnalyticsReadStore`'s own remarks already describe this
family of reports as living at ("pure observability for a human reading a report, at human
frequency"), this is not a measured concern and none is claimed - but it is a real doubling worth
recording rather than discovering later, and if one of these reports ever needs to run at a
materially higher frequency, the two-calls-per-request shape is the first thing to revisit, likely by
computing the preceding period once and caching *facts already read*, not by weakening the ranking
rule.

**A deliberate scope cut, stated so nobody mistakes it for an oversight.** Only the *overall* bucket
of each report gets a preceding-period comparison - never a comparison per channel, per operator, per
tag, per referrer, or per campaign. Building the comparison into every breakdown row would have meant
either running the per-window read twice as many times (still two calls, but each one now needing to
re-derive every dimension's previous bucket) or restructuring every result type in
`Ago.Chat.Application.Abstractions` to carry a nested previous-self, for four reports whose headline
figure is what a site owner actually opens the page to see. `23-17`/`23-18`, or whichever item first
needs a comparison on a breakdown row rather than a headline, is where that tradeoff should be made
deliberately rather than inherited from this item's own convenience.

## Alternatives considered

**A second read-store method taking two windows and returning both bucket sets in one query.** This
would have halved the round trips per request. Rejected: it doubles the surface of every read-store
interface in this codebase's analytics family (eight methods instead of four), and the SQL itself
would need to compute two disjoint windows' worth of aggregates in one statement - either a `UNION
ALL` over two copies of the same `GROUPING SETS` query (real duplication, two places the query logic
can drift apart) or a single query parameterised by two ranges (a genuinely more complex statement
for a feature whose own honesty rule - "computed server-side, in one place" - is about where the
*policy* lives, not about minimising database round trips). The two-calls-through-the-existing-port
shape keeps the query logic in exactly one place per report and pays for the second round trip in
latency this report family does not need to optimise for yet.

**Ranking always by an absolute, never by the rate at all, with the threshold unused.** This would
have made `MinimumSampleForRate` a config value validated at startup and never actually consumed by
any ordering decision - present, but decorative. Rejected because it contradicts the amendment's own
sentence directly: "the threshold ranks, it does not silence" describes a threshold that changes rank
order, not one that exists to be pointed at. The two-tier design (rank by rate above the threshold,
by absolute below it) is the reading that makes the config value load-bearing and testable, and the
one the integration tests prove: raising or lowering `MinimumSampleForRate` visibly changes which row
leads.

**A previous-period comparison per breakdown row, computed by re-running the per-dimension query
twice.** Considered and set aside as this item's own explicit scope cut (see Consequences above) -
not rejected as wrong, just not this item's promise to keep. Filed for whichever later item needs it.
