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

## Open questions

- Interaction with `14-13`'s own visitor-wide preferred channel: whether this item's own per-booking
  priority list overrides it for booking-related messages specifically, or the two are meant to be the
  same list read two different ways — `20-09`'s own file left this open too; decide here, since this is
  the item that actually builds the list.
- Whether this item applies to chat-originated bookings only (matching `20-09`'s own current scope) or
  needs `20-10` to exist first if it is meant to cover widget-originated bookings too.
