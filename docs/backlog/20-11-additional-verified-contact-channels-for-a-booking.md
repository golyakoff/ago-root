# Additional verified contact channels for a booking, priority-ordered

- **Stage**: 20 (and 14 — reuses `14-12`/`14-15`'s own verification mechanisms)
- **Status**: ready
- **Depends on**: `20-09-booking-confirmation-requires-a-verified-phone.md` (built, chat-only) — this
  item is the scope its own Outcome section named as deferred, not built. `14-12-verified-channel-identity-linking.md`
  (done) — the mechanism an additional messenger channel reuses unchanged. `14-15-phone-verification-via-call-or-sms-code.md`
  (done) — the mechanism an additional phone number reuses unchanged.

## What this item is

The second half of the original request `20-09` only partly covers: a visitor can offer more than one
contact channel for a specific booking — another phone number, a Telegram/MAX identity, whatever this
deployment has adapters for — ranked in the priority order the visitor sets, for reminders and
booking-related messages. Each additional channel must independently prove ownership the same way the
primary phone does; a visitor typing "also message me here" is not evidence, the identical "claiming is
not proof" rule `20-09`'s own primary requirement already enforces.

## Why this was deferred from `20-09` rather than built alongside it

`20-09`'s own brief explicitly permitted prioritizing the primary phone gate over half-building both,
given real time/scope pressure — and the implementing worker's own report is honest that this is exactly
what happened: the primary gate shipped complete and tested; this scope shipped nothing. Restated here
as its own item rather than left as a loose end in `20-09`'s own file, per this project's own convention
that a deferred scope becomes a named item, not a silent gap.

## Scope

- A priority-ordered list of additional contact channels, associated with a specific booking (not the
  visitor-wide preference `14-13` already tracks — see Open questions for how the two relate).
- Each additional channel independently verified before it earns a place in the list: `14-15` for another
  phone number, `14-12`'s existing mechanism for a messenger channel with an adapter.
- Storage and the cross-product data shape: apply the identical snapshot pattern `20-09` already
  established for the primary phone (`customers.phone_verified_at`'s own shape) rather than inventing a
  second data-flow pattern — likely a small ordered table (channel kind, address, verified-at, priority)
  keyed to the booking or the customer, decided and recorded here when built.
- Console/widget surface for a visitor to add and reorder channels — the actual UI this item's own
  "priority you can set" language implies; not yet designed, decide when picked up.

## Out of scope

- The actual reminder-sending mechanism that would consume the priority-ordered list — `14-03`/`20-05`
  are both `won't build` today; this item only builds and verifies the list, not a consumer of it.
  Revisit once either reminder-delivery item is picked back up.
- `20-10`'s own public-widget verification mechanism — a different item, though this item's own
  additional-phone case likely wants to reuse whatever `20-10` ends up building for the widget surface,
  if a booking made through the widget is meant to support additional channels too (decide when both
  exist).

## Done when

- [ ] A visitor can add additional contact channels for a specific booking, each refused a place in the
      priority list until independently verified, proven by a test per channel kind exercised.
- [ ] The priority order a visitor sets is stored and retrievable, proven by a test.
- [ ] The cross-product/storage data shape is recorded in this file, following `20-09`'s own snapshot
      pattern or explicitly justifying a departure from it.

## Decided (2026-09-01)

**Relationship to `14-13`: this item *is* the override `14-13` itself deferred, not a second list.**
`14-13`'s own "Out of scope" section names exactly this gap: "a per-conversation override on top of the
visitor-level default — the author's own framing was durable/cross-conversation; a future item can add
a narrower override later without changing this item's own shape." A booking is narrower than a
conversation, so this item's own priority-ordered list is narrower still: a per-*booking* override.
Resolution order for a booking-related message: this item's own list, if the visitor added one for this
booking; otherwise `14-13`'s own `Visitor.PreferredChannelIdentityId`; otherwise today's existing
most-recent-channel fallback, unchanged. Two lists that answer two different questions — "where should
this one booking's reminders go" versus "where should this visitor's replies go by default" — not one
list read two ways.

**Scope stays chat-originated only, structurally, not by choice.** `20-10` now exists, so this is no
longer "wait for a mechanism that doesn't exist" — but the reason to stay chat-only survives anyway,
for a reason specific to *this* item: an additional messenger channel (`14-12`'s own mechanism) can only
ever be verified through an inbound message on a real conversation — there is no such thing as linking a
Telegram identity from a bare, sessionless `POST /book`. A widget-originated booking has no conversation
to link one through, structurally, regardless of whether `20-10`'s own phone gate exists for it. An
additional *phone* number could in principle reuse `20-10`'s own primitive for a widget booking, but
`20-10`'s own frontend (in `ago-widget`) does not exist yet even for the *primary* phone gate — building
a secondary-channels UI on top of a primary flow that has no UI yet would be building on nothing. Revisit
once `ago-widget` actually calls `20-10`'s endpoints.
