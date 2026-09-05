# an operator's work is reported with the load it was carried under

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-03` (the intervals this reads — there is nothing to report without them),
  `23-16` (the rate and comparison rules, or this ships a second, laxer version of them), `23-02`
  (a row a reader can recognise as a person)
- **Decision**: `docs/design/decisions.md` §2's two amendments; §7's rules apply throughout

## Goal

The tenant's per-operator report shows the trade §2 exists to make visible: how many conversations
each operator held, how many of those were **additional**, and what their response times were
**against the load they were carrying at the time**.

Today `/analytics`'s **By operator** table shows conversations, average first response, average
duration and missed — four numbers with nothing to weigh them against. §2's amendment states the
failure exactly: *slow because they were running seven at once* and *slow for no reason* are
identical in a daily average.

## What this may print, and what it may not

§2, and these are constraints on the item rather than notes about it:

- **Absolute numbers lead, and a total is allowed.** Eighty standard conversations taken and closed
  in a minute each may be worth more to a tenant than thirty held open with extras, and only the raw
  figures show that.
- **What is forbidden is a combined score that hides which is which.** No weighting, no index, no
  single "performance" number.
- **The two labels are standard and additional.** The word "forced" appears nowhere a person can read
  it. *Additional* means a conversation held while the operator was already at or past their
  capacity, computed from `23-03`'s interval overlap against `operators.capacity` — not a stored
  flag.
- **A metric is a recorded number, not a judgement.** How volume is weighed against speed when
  evaluating somebody is the author's own formula and is not the product's business. **The product
  counts.**

## Context to read first

- `docs/design/decisions.md` §2 in full, both amendments, and §7
- `docs/design/flows.md` 2.4 in full — including *"must not be made to compete on things outside
  their control"* and *"must not be measured on activity"* — and 4.4
- `docs/design/ui-inventory.md` §5.1 (the **By operator** table), §5.2
- `docs/backlog/23-03-*.md` — the interval store, its overlap query, and the naming rule
- `Ago.Chat.Application/Abstractions/IOperatorAnalyticsReadStore.cs` — the existing per-operator
  buckets and the average-first-response computation this extends rather than re-derives
- `docs/architecture/caching.md` — this is a read; nothing here may be read by a write decision

## Scope

- A read over `conversation_assignments` joined to `conversations` and `messages`, per operator and
  per range: conversations held, of which additional; time to first operator reply; and the operator's
  **concurrent load at the moment that reply was owed**, bucketed. The buckets are configuration, not
  literals in SQL.
- The response returns counts. Any rate goes through `23-16`'s rules — printed with its fraction, and
  never used to order rows below the threshold.
- **It extends the existing per-operator table rather than creating a fifth report screen.**
  `/analytics` is where a tenant already reads per-operator numbers; a second screen with the same
  subject is the crowding `OperatorAnalyticsPage`'s own doc comment already argues against for a
  second dimension.
- **Attribution stated on the screen**: what this counts is conversations this system handled, and
  the load is this system's own view of it. An operator who was also cutting hair is not in it.
- Tenant isolation proven for the new read, the same way every sibling report proves it.
- **No aggregate table and no read model.** §2: a read model is added when a report is measurably
  slow, and "measurably" means a run in `load/` (`CLAUDE.md` rule 7). If the overlap query is slow on
  a realistic fixture, say so with the number and file the read model as its own item.

## Out of scope

- **Contact-reveal counts.** `23-11`'s amendment: they belong in an audit view, never in the report a
  person is judged on. The operator who calls customers back reveals forty numbers and the one who
  does not reveals two, and a manager reading that punishes the useful one — who then stops calling,
  to protect their figure.
- Any ranking of operators against each other, any target, any combined score.
- Activity measures — keystrokes, messages sent, conversations opened. `flows.md` 2.4 forbids them by
  name: gamed trivially, and they punish the operator who solved it in one good answer.
- The operator's own view of these figures — `23-18`.
- Outcome as a dimension. Response-time-against-outcome is a different cut of §7's list and is not
  filed; see the stage report.

## What remains, found 2026-09-05 while building `23-18`

**The backend half of this item shipped. The console half never did**, and the item's own Scope is
explicit that the console is in it — *"it extends the existing per-operator table rather than creating
a fifth report screen"* — so the first Done-when above is false, not merely untested.

Verified against `origin/main` rather than inferred:

| | |
|---|---|
| `Ago.Chat.Contracts.OperatorAnalyticsOperatorBucketDto` | carries `OperatorLoadSummaryDto? Load`, added by this item |
| `ago-console` `OperatorAnalyticsOperatorBucketDto` (`types.ts`) | declares `operatorId`, `bucket`, `operatorName` — **no `load` at all** |
| `OperatorAnalyticsPage.tsx` | zero references to it |

So a tenant cannot see, for their own team, the standard/additional split this item computes and sends.

**This does not become a new number.** It is one promise — *an operator's work is reported with the
load it was carried under* — in two places, and CLAUDE.md rule 15's 2026-09-03 amendment is explicit
that the same promise in two places is one ticket even where the code is trivially separable. Splitting
it would leave a closed ticket claiming a report nobody can read.

**It is now the more urgent half, not the leftover one.** `23-18` shipped the operator's own view of
the same figures, so an operator sees their split and their manager does not — the asymmetry runs
backwards from what either item intended.

## Done when

- [ ] The per-operator table shows standard and additional as separate absolute counts, with a total,
      and no figure combines them.
- [ ] Response time is reported per load bucket, and a fixture with a known overlap produces the
      expected bucketing.
- [ ] An operator who never exceeded capacity shows zero additional and is not thereby made to look
      worse or better — asserted, because a zero in a comparison column is the easiest thing to
      render as a criticism.
- [ ] The word "forced" appears in no user-visible string in either repository.
- [ ] `23-16`'s rules hold on every rate this screen prints.
- [ ] Another tenant's per-operator figures cannot be read.
- [ ] A conversation an operator held twice (transferred away and back) is counted once as a
      conversation and twice as an interval, and the screen says which it is showing.

## Open questions

None.
