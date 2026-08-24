# AGO Inbox × AGO Calendar: unattended booking through a channel

- **Stage**: 21
- **Status**: blocked — a real, unresolved UX-design question (below); no implementation starts until
  the author picks a direction
- **Depends on**: at least one of `14-02`/`14-03`/`14-05` (a real inbound channel to book through) and
  `20-03`/`20-04` (a real booking flow to reach) — this is why this item is sequenced in Stage 21,
  after both Stage 14 and Stage 20, rather than inside either

## Goal

A visitor reaches AGO Calendar's own booking flow directly from a channel — MAX, SMS, or whichever
others by the time this item is picked up — 24/7, with no operator involved at all, when the tenant has
enabled it (a tenant-toggleable feature, off by default, mirroring `14-04`'s own toggle shape). This is
the second of the two genuinely new capabilities the product spec names for AGO Inbox, distinct from
"just connect more channels" — and it is deliberately not solved by this item's own scope, because the
underlying UX question has no established answer to build against yet.

## Context to read first

`docs/backlog/20-03-booking-and-lead-card.md` and `20-06-console-and-booking-widget.md` — the real
booking flow this item would eventually drive, including the widget's own rich UI (worker photos, a
slot grid, a click to pick one) that a channel conversation categorically does not have. `docs/backlog/
14-01-external-channel-identity-and-inbound-port.md` — the channel-message pipeline this item's own
flow would need to hook into, on the AGO Chat side, before handing off to AGO Calendar's separate API
(a genuine cross-product call, `ago-chat` → `ago-calendar`, the first one either product's own backlog
has needed — state explicitly, once a direction is chosen, whether this is a direct HTTP call from
`Ago.Chat.*` to `Ago.Calendar.Api`'s own public booking endpoint, treating it as an ordinary external
dependency the same way a webhook target is, or some other integration shape).

## Scope — deliberately not written as an implementation plan

This item's only real scope, until the open question below is answered, is naming and lightly
investigating the three candidate directions the product spec identifies, without building any of them
speculatively:

- **A step-by-step Q&A text tree.** Works on every channel including bare SMS (no buttons needed at
  all), but slow — several message round-trips for one booking. The simplest to build, the worst
  experience.
- **A channel-adaptive UX.** Richer where the channel supports it (Telegram inline buttons), plainer
  where it does not (SMS falls back to the text tree above). More engineering surface — effectively two
  or more booking flows to maintain instead of one.
- **Free-text natural-language understanding.** The most ambitious, and — stated explicitly, since it
  is a real technical connection worth naming rather than treating the two as unrelated — likely the
  same underlying AI investment as `14-04`'s own deferred LLM-backed auto-reply variant, not a separate
  one; if the author decides to build the LLM auto-reply variant for real, this direction becomes
  markedly cheaper to also build, and that dependency should inform which order the two eventually get
  picked up in, once both are unblocked.

## Out of scope

- Building any of the three directions — genuinely blocked, not a default-to-simplest fallback; picking
  the text-tree direction "because it's easiest" without the author's own decision would be exactly the
  kind of invented answer this repository's own conventions warn against (`backlog/README.md`: "An item
  with an unanswered open question does not get started; ask the author instead").
- The console/tenant-facing toggle for enabling unattended booking on a channel — trivial once a
  direction exists, not worth scoping ahead of the real decision.

## Done when

Not yet meaningful — this item has no `Done when` until the open question below is answered and the
item is re-scoped as a real implementation plan for whichever direction is chosen.

## Open questions

**Which of the three candidate UX directions to build, if any** — genuinely unsolved, named plainly per
the author's own explicit instruction not to invent an answer here. A reasonable next step, once this
item is picked up for real, is a small, real user-facing prototype of the cheapest direction (the text
tree) against one already-shipped channel, specifically to generate a real opinion about how bad "slow
but universal" actually feels before committing to the more expensive channel-adaptive or NLU
directions — but that prototype is itself a decision for the author to make, not assumed here.
