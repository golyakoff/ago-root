# a rate is never printed without the figures it came from, and nothing is ranked on a thin one

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §7, including the *show the absolute numbers instead of
  refusing to print the rate* amendment (2026-09-04)

## Goal

Every number the four report screens print can be judged by the person reading it: a rate carries the
fraction it was computed from, a figure carries the preceding period to compare it against, and
nothing is ordered by a rate built on two conversations.

## What the amendment changed, and what the code actually is

§7 originally said the product refuses to conclude below a threshold. The amendment reverses that:
**refusing hides information; "50% (1 of 2)" is fully honest and lets the reader judge the sample
themselves.** The threshold survives only for **ranking**.

The amendment then says the decision "retroactively breaks" `/analytics/conversion`, which "prints a
per-operator conversion rate today with no threshold and no absolutes at all." **Checked against the
code, that is half right, and the half that is wrong matters for scoping** — say so in the branch
rather than discovering it:

- The **server side already returns the absolutes.** `ConversionReportResult` and
  `ConversionReportResponse` carry `ConvertedCount`, `NotConvertedCount`, `FollowUpNeededCount`,
  `UnsetCount` and `RecordedCount` beside `ConversionRate`, and `ConversionRate` is already `null`
  when `RecordedCount` is zero. `TagBreakdownResult` carries the identical set.
- The **console already renders them as separate columns** — `ConversionReportPage` has six columns,
  four of them counts.
- What is genuinely missing is the pairing: the rate cell renders
  `` `${(rate * 100).toFixed(1)}%` `` and nothing else, four columns away from its own denominator.
  There is **no threshold anywhere**, there is **no comparison period**, and the per-operator query
  has **no `ORDER BY` at all** — so today's row order is whatever `GROUP BY GROUPING SETS` happens to
  produce.

## The rules this implements

- **Never a bare number.** A figure alone means nothing; what makes it mean something is a pair —
  against the preceding period, against another segment, or best of all the same figure under
  different conditions.
- **Dynamics, relative and absolute together.** "+50%" without "two against three" congratulates a
  tenant on randomness — and the smallest tenants, the first ones, are where this bites.
- **The threshold ranks, it does not silence.** Operators must not be sorted by a rate built on two
  conversations, even with the raw figures beside it.
- **Attribution claims only what can be traced.** A booking made in the widget after a conversation
  is ours; a customer who phones a week later is not, and saying otherwise invites a check we would
  lose.

## Context to read first

- `docs/design/decisions.md` §7 in full, including what it rejects and the amendment
- `docs/design/flows.md` 4.4 — "must never happen: inflated, flattered, or selectively-good numbers",
  and the failure branch where the honest answer is *it is not paying off yet*
- `docs/design/ui-inventory.md` §5 in full — four screens, no chart, every number a table cell, and
  the two screens with date presets against the two without
- `Ago.Chat.Application/Abstractions/IOperatorAnalyticsReadStore.cs`,
  `IConversionReportReadStore.cs`, `ITagBreakdownReadStore.cs`, and the four `Get*ReportForSite*`
  handlers
- `Ago.Chat.Infrastructure.Postgres/ConversionReportReadStore.cs` — its grouping-sets query, and the
  absence of an ordering

## Scope

- **The rate is rendered with its fraction, inline**, on `/analytics/conversion` (both tables) and
  `/analytics/tags`. `50.0% (1 of 2)`, not a percentage whose denominator is four columns away.
- **A `MinimumSampleForRate` option** in configuration, with a stated default, applied to **ordering
  only**: a report may not sort rows by a rate whose denominator is below it. Where a report ranks,
  it ranks by an absolute; where it does not rank, it has a **stable, stated order** — which is a
  change in itself, because today it has none.
- **A comparison window.** Each of the four handlers returns the same figures for the preceding
  period of equal length, as counts, so the console can show absolute and relative change together.
  Computed server-side, in one place, rather than by the console calling twice — the window rule is
  the honesty rule, and it must not live in a browser.
- **All four handlers** — `GetOperatorAnalyticsForSiteHandler`, `GetConversionReportForSiteHandler`,
  `GetTagBreakdownReportForSiteHandler`, `GetModuleFlowReportForSiteHandler` — because a rule applied
  to three screens is a rule the fourth disproves.
- The permanent caveat alerts that already exist (`/analytics/conversion`'s "as operators have
  recorded it", `/analytics/booking-flow`'s three-sentence caveat, `/analytics`'s referrer note) are
  kept and checked against the attribution rule; where one claims more than can be traced, it is
  corrected here.

## Out of scope

- **Any valuation or forecast.** §7 rejects both outright, including the proposal to ask the tenant
  for an average cheque and multiply. We cannot know what an answer was worth.
- Refusing to print a rate. The amendment reversed that, and an implementation that hides a thin rate
  is implementing the superseded decision.
- New cuts of the data, and anything built on `23-03`'s intervals — `23-17`.
- Charts. `ui-inventory.md` §5 records that no report contains one; whether they should is the design
  pass's answer.
- The operator's own view of these numbers — `23-18`.

## Done when

- [ ] Every rendered rate on `/analytics/conversion` and `/analytics/tags` shows its numerator and
      denominator in the same cell, including a rate of `100% (1 of 1)`.
- [ ] A rate whose denominator is zero still renders as it does today, not as `0%`.
- [ ] Each report returns the preceding equal-length period, and the console shows the change in
      absolute and relative terms together.
- [ ] Row order is deterministic and stated, and no ordering uses a rate below the threshold — a
      test, not a convention.
- [ ] A tenant-isolation test covers the comparison window's own query, the same way every sibling
      report proves it.
- [ ] `nfr.md` or `data-model.md` — whichever owns it — records the threshold and that it is
      configuration, not a constant.

## Open questions

None.
