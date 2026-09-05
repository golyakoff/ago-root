# ADR-0107: An operator's load is a second, independently-windowed read over the same intervals

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 23

## Context

`23-17` extends `/analytics`'s existing per-operator table with the numbers `docs/design/decisions.md`
§2 exists to make visible: how many conversations an operator held, how many of those were
**additional**, and their response time against the concurrent load they were carrying. `23-03` already
stores the raw fact these numbers come from - `conversation_assignments`, an append-only interval per
assignment - and already proves, in `ConversationAssignmentOverlapQueryTests`, that "how many did this
operator hold at instant T" is answerable from those rows. Nothing had called it yet.

`IOperatorAnalyticsReadStore` already computes a per-operator breakdown for the same page - conversation
count, average first response, average duration, missed count - but it answers a different question,
windowed a different way: it attributes a conversation to whoever **replied to it first**, regardless of
who transferred it away afterwards, and it windows by `conversations.created_at`. `23-17`'s own question
is "which operator's own assignment interval was this", windowed by `conversation_assignments.started_at`
- a conversation an operator held twice (transferred away and back) must count once as a conversation
and twice as an interval, which the attribution-based store has no way to represent since it has no
notion of an interval at all.

## Decision

**A new port, `IOperatorLoadReportReadStore`, not a fifth method on `IOperatorAnalyticsReadStore`.**
That interface's own remarks already draw this line for `IConversionReportReadStore`/
`ITagBreakdownReadStore`/`IModuleFlowReadStore` - "a genuinely different query shape" gets its own port.
This one qualifies twice over: it joins `conversation_assignments` (a table
`IOperatorAnalyticsReadStore`'s own query never touches), and it windows by a different column
(`started_at`, not `created_at`) than every other report on the page.

**"Additional" is computed from interval overlap against `operators.capacity`, at the instant an
interval starts, counting the interval itself.** `ConversationAssignmentOverlapQuery.CountHeldAtAsync`
already proves this shape against a known fixture; the new read store applies the identical predicate
(`started_at <= this interval's own started_at`, still open or ending strictly after it) per interval in
the window, via a correlated subquery, rather than a fourth call into `IConversationAssignmentLog`. A
concurrent load **equal to** capacity is **standard** - it fills the last open slot, it does not exceed
it; `23-03`'s own naming section states this precisely ("the second only happens once capacity is
full"). Nothing is stored: `ConversationAssignmentSource` still has exactly two members.

**Held, not attributed.** `IOperatorLoadReportReadStore.ConversationsHeld` counts distinct
`conversation_id`s among an operator's own intervals in the window; `IntervalsHeld` counts the intervals
themselves. A conversation transferred away and back to the same operator is one conversation, two
intervals - the two numbers are reported side by side on the console screen precisely so a reader is
never left to guess which one they are looking at (Done-when's own words: "the screen says which it is
showing").

**Response time is bucketed by the operator's own concurrent load at the moment the interval started,
and the buckets are configuration (`AnalyticsOptions.LoadBucketUpperBounds`), never literals in SQL.**
The query returns one row per exact concurrent-load integer per operator; `OperatorLoadBuckets`, a pure
function in `Ago.Chat.Application`, folds those rows into the configured buckets in C#. This mirrors
`PrecedingPeriod`'s own split: the mechanism (Postgres, an exact integer) sits in Infrastructure, the
policy (which integers count as "the same bucket") sits in Application, testable with no database.

**Two queries against the same `in_window`/`loaded` CTEs, not one `GROUPING SETS` query.** A totals row
per operator (`IntervalsHeld`, `ConversationsHeld`, `StandardIntervals`, `AdditionalIntervals`) comes
from a plain `GROUP BY operator_id`; the per-load breakdown comes from a second statement grouping by
`(operator_id, concurrent_load)`. `OperatorAnalyticsReadStore`'s own sibling query already computes five
dimensions from one `GROUPING SETS` statement successfully, and an early version of this store did the
same for its two - a `GROUPING SETS ((operator_id), (operator_id, concurrent_load))` shape, disambiguated
by `grouping(concurrent_load)` the same way that file's own `OperatorGrouping` flag works. It was kept
split anyway, once a genuine bug elsewhere (the row type declaring `concurrent_load` as `int?` when
Postgres's own `count(*)` is always `bigint`, which failed every row outright with a Dapper mapping
exception) was fixed and the combined query then computed every number correctly against the fixture
below, `count(distinct conversation_id)` included: the split removes any need for a reviewer to reason
about whether a `DISTINCT` aggregate behaves correctly across multiple grouping sets sharing a common
prefix, at the cost of one more round trip and the CTEs repeated in both statements - both acceptable at
this report family's own human-frequency volume (`IOperatorLoadReportReadStore`'s own remarks: pure
observability, no write decision depends on it, `CLAUDE.md` rule 8).

**No preceding-period comparison for the load report.** `23-16`/`adr/0103` scoped that comparison to each
report's own headline bucket - the overall total, never a breakdown row. The load summary is a
per-operator breakdown, the same category `adr/0103`'s own "Consequences" section already names as out
of scope for this reason; adding one here would be inventing a rule `23-16` deliberately did not build.

**The handler merges by the union of operator ids, not the intersection.** `GetOperatorAnalyticsForSiteHandler`
now calls three read-store methods concurrently (`Task.WhenAll`) and joins the attribution-based
per-operator rows with the load-report rows on `OperatorId`. An operator present in one list but not the
other still gets a row - a zero `Bucket` for one with no attributed conversation, a `null` `Load` for one
with no assignment interval in the window at all (a real "no data", never rendered as a zero) - because
Done-when requires an operator who never exceeded capacity to show a real, present `0`, not to vanish
from the table because their only conversations this window happened to be answered by someone else.

## Consequences

**Positive.** The report reuses `23-03`'s own overlap proof and `23-16`'s preceding-period/threshold
machinery (by explicitly declining to double it: no rate is printed here, so `AnalyticsOptions.MinimumSampleForRate`
plays no part, the same "no ranking hazard" reasoning `OperatorAnalyticsReadStore`/`ModuleFlowReadStore`
already state for their own non-rate numbers). No EF migration, no new table, no aggregate - exactly
`23-17`'s own Scope. The bucket-labelling function is a five-line pure static method with its own unit
tests, no database required to prove it.

**Negative.** The per-operator table now issues three read-store calls per request instead of two - the
same "worth recording, not a measured concern yet" caveat `adr/0103`'s own Consequences section already
gives for its own doubling. A future high-frequency caller would need to revisit this, not by weakening
`23-16`'s comparison rule, the same warning that ADR already states for itself.

## Alternatives considered

**A fifth method on `IOperatorAnalyticsReadStore`.** Rejected: it would force that store's own
`GROUPING SETS` query to also join `conversation_assignments` and window by a second, different column,
turning one already-large query into two windowing rules braided together - exactly the "genuinely
different query shape" case that interface's own remarks already carve out for three sibling reports.

**Storing a stored `IsAdditional` flag on `conversation_assignments` at write time.** Rejected outright:
`decisions.md` §2 and `23-03`'s own Scope are explicit that this table stores raw facts and nothing
derived - a stored flag would need a write-time capacity read for every assignment, reintroducing the
exact coupling `23-03` was built to avoid ("no write decision depends on this table," `CLAUDE.md` rule
8), for a number a read can compute for free.

**A single combined `GROUPING SETS` query for totals and per-load breakdown.** Considered, prototyped,
and in the end functioned correctly once the unrelated row-mapping bug was fixed - see the Decision
section above for why it was kept split anyway (reviewer cognitive load, not correctness).
