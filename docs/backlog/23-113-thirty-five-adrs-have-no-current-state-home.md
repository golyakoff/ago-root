# thirty-five ADRs have no current-state home

- **Stage**: 23
- **Status**: done
- **Depends on**: `adr/0156`, which established the split this closes the gap in.
- **Found**: 2026-09-08, measured while accepting `adr/0156`.

## What the gap is

`adr/0156` makes `docs/architecture/*` and `docs/conventions/*` authoritative for **what holds now**,
and leaves the ADR authoritative for **why**. That works only while every decision is reachable from a
current-state document.

**Ninety-four of 129 ADRs are. Thirty-five are not**, including `0001` and `0002` — the two that
establish how decisions are recorded and how the layers depend on each other.

`tools/queue-audit.sh` names all thirty-five on every run, and will keep naming them until each is
placed.

## Why this is not cosmetic, and not urgent either

**Not cosmetic**, because an unreferenced ADR is exactly the failure `0156` warns about: a
current-state document that silently omits a decision gives a *confident wrong answer*, which is worse
than the slow reconstruction the split replaced. Every one of these thirty-five is a decision that a
reader trusting the documents will not find.

**Not urgent**, because the situation is no worse than it was before `0156` — the corpus was always
the only complete source, and it still is. What changed is that the gap is now counted instead of
invisible.

## The thirty-five, grouped by what they are

The grouping matters, because they are not one kind of work:

- **Foundational, and probably a one-line reference each**: `0001`, `0002`, `0023`. These are cited
  constantly in prose but never by the pattern the check looks for.
- **Calendar and booking decisions** — `0081`-`0090`, `0104`-`0107`, `0110`, `0125`, `0136`, `0143`,
  `0147`, `0148`. The largest group, and the one that most needs a home: AGO Calendar's own
  current-state documentation is thinner than AGO Chat's, which is why they had nowhere to land.
- **Product, commercial and consent decisions** — `0073`, `0082`, `0106`, `0127`, `0146`, `0151`,
  `0152`, `0153`, `0155`. Several concern entitlement and configuration, and `docs/architecture/`
  has no page that owns that boundary yet.
- **Naming, hosting and deployment** — `0091`, `0092`, `0140`, `0144`. `edge.md` and the runbooks are
  the likely homes.
- **One malformed file**: `0077` opens with a byte-order mark and a title line that reads
  `﻿# 0077: ...` rather than `# ADR-0077: ...`. Worth fixing while in there.

## Where this is likely to go wrong

- **Referencing is not the goal; being findable is.** Adding `adr/0087` to a document as a bare
  citation satisfies the check and helps nobody. The document has to *say what holds* and cite the ADR
  for why — otherwise this becomes thirty-five link-drops and the check starts lying, which is worse
  than the check failing.
- **Some of these will reveal a missing document, not a missing sentence.** The entitlement group in
  particular has no page that owns it. Writing one is the honest answer; wedging the decisions into an
  unrelated page is not.
- **Do not edit the ADRs.** They are immutable (`adr/0156`); this item changes documents, not
  decisions. The single exception is `0077`'s malformed header, which is a file defect rather than a
  change to what was decided.
- **This is judgement work, not mechanical work.** Each ADR has to be read to know what current-state
  sentence it implies. It does not amortise the way a slice with a test suite does.

## Done when

- [x] `tools/queue-audit.sh` reports no ADR without a current-state home. **The count started at 35
      and was wrong**: the check looked only at `architecture/` and `conventions/`, so it called 15
      correctly-placed ADRs orphans - `adr/0144` lives in `runbooks/redeploy.md` and `adr/0136` in
      `roadmap.md`, which are exactly the right homes. Widened to all of `docs/` except `adr/` (they
      cite each other) and `backlog/` (an item is a proposal, and nearly every ADR is cited by the
      item that produced it, so counting those would make the check pass universally). Real number: 18.
- [x] Each reference is a sentence saying what holds, citing the ADR for why. The clearest case is
      `adr/0002`: it had always pointed *at* `clean-architecture.md` ("the what-goes-where table lives
      there") and the document had never pointed back, so the link ran one way and the reader arriving
      at the document learned nothing about where the rule came from.
- [x] Two groups had no owner and now have one page between them:
      `docs/architecture/entitlements-and-subscriptions.md`, carrying `adr/0151` (entitlement is the
      platform's, configuration is the tenant's) and `adr/0073` (the renewal job, `PastDue` versus
      `Lapsed`, and why the idempotence key is deterministic). They are one page because they are one
      question at two moments - *may this account do this* and *is it still paid for* - and both were
      scattered across five documents that each mentioned them and none of which owned them.
      Prices and tiers stay out: they are `ago-business`'s, and private.
