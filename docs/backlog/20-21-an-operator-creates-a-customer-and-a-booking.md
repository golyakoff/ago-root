# An operator creates a customer and a booking

- **Stage**: 20
- **Status**: ready
- **Decided by**: `adr/0090` — read it first. This item builds what it decided and does not re-open it.
- **Depends on**: `20-20` (nothing here is verifiable by hand until AGO Calendar runs somewhere).

## Why this is the first booking item

The first tenant is a single-person business. Her clients arrive **by telephone and in person about as
often as through her website** — her own words. Today the console can `reject`, `cancel` and `no-show`
an **existing** booking, and nothing creates one: bookings originate only in a chat conversation or in
the public booking API, which ships disabled.

So she cannot enter a booking for someone who just called her. This is not a missing convenience; it is
her primary workflow with no implementation.

## What exists, checked before scoping

- `Customer` already carries `Phone` and a nullable `PhoneVerifiedAt`, with `Register(...)` and an
  idempotent `RecordVerifiedPhone(...)`. **The two-level trust model this item needs already exists** —
  "she typed it, nobody proved it" is expressed by the timestamp being absent.
- `Customer.Phone` is **immutable**: no setter, no correction path.
- `20-10`'s phone-verification primitive exists and works; no operator-facing way to start it.
- Slot claiming is `adr/0059`/`adr/0086`'s compare-and-set. A third caller must go through the same
  use case, not a third copy of the rule.

## Scope

- **Create a customer** from the console: display name and phone. `PhoneVerifiedAt` stays null —
  `adr/0090` decides that an operator-created booking is never blocked on verification, because she is
  on the telephone and cannot wait for a code round-trip.
- **Find an existing customer** before creating one, by phone or name. She recognises regulars, and the
  product must let her attach a booking to the person rather than making a second record of them.
  **Phone numbers must be normalised for this to work at all** — `+7`, `8`, spaces and brackets have to
  collapse to one form, or the search misses the person who is already there and she creates the
  duplicate the search existed to prevent.
- **Create a booking** for that customer against an available slot, through the *same* claim path the
  other two origins use.
- **Correct a phone number**, which **clears `PhoneVerifiedAt`** (`adr/0090`: verification is evidence
  about a value, not about a person). A mistyped digit is the most likely daily error in this entire
  workflow and there is no fix for it today.
- **Start a verification** from the console when she wants one — the primitive exists, the button does
  not. Optional, never blocking.

## Out of scope

- The confirmation message that doubles as verification (`adr/0090`). **No SMS provider is chosen yet**
  — the author's own decision — so it cannot gate this. The model must not preclude it; nothing waits
  for it.
- Reschedule (`20-22`) and visit outcomes (`20-23`).
- Reopening `20-09`'s verified-phone rule. `adr/0090` scoped it to two of three origins; that is settled.
- The public booking API's exposure.

## Done when

- [ ] An operator can create a customer and book them into an available slot, end to end, and the slot
      is genuinely claimed — proven against the same invariants the other origins obey, not by a
      separate code path that happens to write the same rows.
- [ ] Searching by a phone typed in a different but equivalent form (`+7…`, `8…`, with spaces) finds
      the existing customer. Proven with the awkward forms, not the tidy one.
- [ ] Correcting a phone clears its verification, proven by a test that fails if the timestamp survives.
- [ ] A booking created this way is **valid with an unverified phone** — and a chat-originated one
      still is not, so `20-09` is shown to be scoped rather than abandoned.
- [ ] No path exists by which this creates a booking that violates `adr/0049`'s no-overlap or
      `adr/0086`'s claim — the third caller is the third chance to bypass a rule by not going through
      the same handler.

## Open questions

- **Does she need a display name at all**, or is a phone enough on day one? A name is what makes the
  search useful for regulars; a required name is one more field while a client waits on the line.
- **What happens when two customers legitimately share a number** — a couple, a family. Refusing is
  safe and might be wrong; `adr/0090` only rules out reputation attaching to the *number*.
