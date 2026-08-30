# Conversation outcome, and a conversion report built on it

- **Stage**: 18
- **Status**: ready
- **Depends on**: `18-08-basic-operator-analytics.md` (done) — the read-store shape this item's report
  extends

## Goal

An operator can mark what a conversation actually led to (an order, no sale, a follow-up needed), and a
site owner can see a real conversion rate — "how much benefit is the business actually getting from
paying us", the second half of what `ago-business/docs/decisions/0009` names Jivo as already reporting
("воронка продаж" — the sales funnel) that AGO does not.

## Why this is a new write path, not just a new report

Every other analytics item this stage has built (`18-08`, `18-09`) derives its numbers entirely from
data this system already records for other reasons — nobody had to add a column to make first-response
time or missed-count computable. Conversion is different: **AGO Chat has no concept of an order or a
sale anywhere in its data model**, and `ago-business/decisions/0009`'s own Level 4 rejection (CRM/
e-commerce depth is a different product) means this item cannot and should not build a real integration
with the shop's own order system to get that data honestly. The only shape that stays inside this
project's own boundary is an **operator-reported outcome** — a closed, small vocabulary the operator
picks, not a verified sale record pulled from anywhere external. State this plainly in the report's own
UI, not just in this document: a conversion rate built from operator-reported outcomes is a real,
useful number, and it is also **not** the same claim as "N% of chats resulted in a verified sale" —
conflating the two would misrepresent what was actually measured, the same discipline `18-08`'s own
first-response-time definition already holds itself to.

## Scope

- **Domain**: a closed `ConversationOutcome` enum — `Unset` (the default, every existing and new
  conversation until an operator sets it), `Converted`, `NotConverted`, `FollowUpNeeded`. Kept small and
  closed on purpose, matching `MessageAuthorKind`'s own "closed vocabulary, not free text" precedent —
  a free-text outcome field would be unreportable and would need its own moderation/parsing story this
  item does not need to invent.
- A nullable-with-default column on `conversations` (or a sibling table if the domain model argues for
  one once actually written — decide the same way `18-04` decided notes deserved their own table) —
  `Unset` for every conversation until an operator explicitly changes it, so no backfill migration
  pretends historical conversations have an outcome they were never asked about.
- A `SetConversationOutcomeHandler`, gated on the same permission `CloseConversationHandler` already
  uses (an operator who can close a conversation can record what it led to) — settable independent of
  close, since an operator may know the outcome before or after closing.
- A console control (a small set of buttons or a dropdown, not a form) on the conversation view,
  optional — this item does not make setting an outcome mandatory to close a conversation; forcing it
  is a UX-friction decision this item explicitly declines to make unilaterally.
- A conversion report extending `18-08`'s own site-wide numbers and `18-09`'s per-operator ones:
  conversion rate = `Converted` ÷ (`Converted` + `NotConverted`) — **`Unset` conversations excluded from
  the denominator entirely**, stated as the load-bearing decision it is: including them would silently
  conflate "operators chose not to convert this" with "nobody has recorded an outcome yet," which is
  not the same fact and would make the reported rate meaningless the moment adoption of the new control
  is anything less than universal (the realistic case, especially at first).
- Date-range presets (`18-11`'s own scope names this identically; build once here if this item lands
  first, reuse rather than duplicate) — calendar-month buckets alongside the existing free `from`/`to`
  range, since "conversion this month vs last month" is the shape a site owner actually wants to
  compare.

## Out of scope

- Any real integration with a shop's own order/payment system — rejected by `0009`'s Level 4 call, not
  reopened here.
- Making outcome-setting mandatory, or reminding/nagging an operator to set one — a real UX decision
  this item leaves to a future pass once real usage shows whether voluntary adoption is high enough for
  the number to be meaningful.
- A "why not converted" free-text reason — closed-vocabulary discipline again; if this is wanted later
  it is its own scoped addition, not implied by this item.

## Done when

- [ ] An operator can set a conversation's outcome to any of the three real values from the console,
      proven by a test.
- [ ] The conversion report computes the rate correctly against real seeded data spanning all three
      outcomes plus `Unset` conversations, proven by a test that specifically checks `Unset`
      conversations are excluded from the denominator, not just that the happy-path numerator is right.
- [ ] Date-range presets (calendar month, previous calendar month, last 30 days) are available in the
      console alongside the existing free-form range, and the effective computed range is echoed back
      by the server the same way `18-01`'s search already does — never a silently-assumed client-side
      date.
- [ ] Cross-site isolation is proven by a test.

## Open questions

None left open — the denominator decision above is this item's own call, argued and recorded, not left
for a future session to rediscover by noticing the number looks wrong.
