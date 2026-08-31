# Public booking widget requires a verified phone

- **Stage**: 20 (and 14 — likely consumes or mirrors a `14-15`-shaped mechanism)
- **Status**: ready
- **Depends on**: `20-09-booking-confirmation-requires-a-verified-phone.md` (built, chat-only) — this
  item is the named follow-up its own Outcome section points to, extending the identical guarantee to
  the one calling surface `20-09` deliberately left untouched. `14-15-phone-verification-via-call-or-sms-code.md`
  (done) — the mechanism this item most plausibly extends or mirrors; see Scope below for why "extends"
  is not yet decided.

## Why this exists, stated plainly

Not a hypothetical someday. Named by the author as a real prerequisite to launching this product with
its first live customer, in the same conversation `20-09` itself came from — a public, embeddable
booking widget that cannot complete a booking at all (`20-09`'s own honest consequence, deliberately
accepted there and fixed here) is not a shippable product for a real shop's own site.

## The problem `20-09` could not solve, restated precisely

`Ago.Calendar.Api`'s public `POST /calendars/{id}/events/{id}/book` endpoint is unauthenticated and
directly reachable from any page on the internet — that is its whole design, not a gap (`Customer` has
no account by construction, `20-01`). `20-09`'s own gate needs a caller to *assert* verification; an
anonymous endpoint cannot be given a self-asserted field to do that without handing every caller a way
to forge it, which would make the guarantee this item's own family exists to build worthless for the
one surface a real, unassisted customer is most likely to use.

`14-15`'s own mechanism (`ago-chat`) cannot simply be called from this endpoint either, and this is
worth stating precisely rather than waved through: `adr/0027` makes `Ago.Calendar` an independently
deployable product with **no dependency on `Ago.Chat` existing at all**. A public booking widget that
silently required a running `ago-chat` deployment to verify a phone would violate that boundary for
every booking, not only chat-originated ones — the opposite of `20-09`'s own care to keep the two
products' trust boundaries honest.

## The three real shapes, weighed but not chosen

- **(a) The widget calls `ago-chat`'s own `14-15` endpoints directly, cross-product.** Rejected as the
  default: reintroduces the exact `adr/0027` violation named above. Only worth reconsidering if a future
  decision makes AGO Calendar's own deployment genuinely always-paired with AGO Chat (no evidence of
  that today — the two are sold and can be run independently).
- **(b) Reuse an already-verified phone from a prior chat-originated booking.** `customers.phone_verified_at`
  (`20-09`) already holds this, keyed by phone within a tenant. Cheap, and correctly serves a *returning*
  customer with zero new mechanism. Does nothing for a first-time visitor with no prior verified booking
  — which, for a shop's very first live customer, is the common case, not the edge case. A partial
  mitigation, not a solution, and should probably ship regardless of which of (a)/(c) is chosen, since
  it costs little and helps every returning customer immediately.
- **(c) AGO Calendar builds its own phone-verification primitive**, structurally mirroring `14-15` (a
  pending-verification aggregate, a proactive SMS/voice send, lockout, rate limiting) but in
  `Ago.Calendar`'s own repository, with no cross-product call. Keeps the product boundary genuinely
  intact — Calendar remains deployable and bookable with zero `ago-chat` dependency, exactly as
  `adr/0027` requires. Costs real, duplicated engineering: a second implementation of substantially the
  same mechanism `14-15` already built, in a second codebase, with its own SMS/voice gateway account (a
  second real cost, or a shared account if the deployment operator chooses to reuse one — a
  deployment-config question, not a code-sharing one, since `Ago.Platform.*` has no phone-verification
  package to share it through and inventing one now would be exactly the premature platform
  generalisation `clean-architecture.md` warns against for two products with only one real consumer
  each so far).

**Leaning, not deciding here**: (c), on architectural-boundary grounds, with (b) built alongside it
regardless as a low-cost improvement for returning customers. Record the actual decision, and the
reasoning if it differs from this lean, in this item's own file when picked up — this section states
the tradeoffs so the choice is not made blind, not so it is made here.

## Scope

- The chosen verification shape from above, built and wired into `BookingEndpoints.cs`'s own request
  handling — `BookEventRequest` gains whatever field(s) the chosen shape needs (a verification token, a
  short code alongside the phone, or similar — shape depends on the decision above).
- `BookEvent.RequiresVerifiedPhone` set `true` for this endpoint once the mechanism exists — the one
  line `20-09` deliberately left as `false`, becoming `true` is this item's own actual "done" signal at
  the code level.
- If (b) is included (recommended regardless of (a)/(c)): the endpoint checks `customers.phone_verified_at`
  for a match on the asserted phone before requiring a fresh verification round — a cheap, real
  improvement for a repeat customer.
- Live verification against a real phone number and a real gateway account — the same bar `14-15` itself
  could not clear in this environment; if this item ships before an account exists, name that gap
  honestly rather than asserting success by inspection, matching this codebase's own established
  discipline for every other unverified-live channel.

## Out of scope

- `20-11`'s own additional-channels scope — a different item, though likely built on the same
  verification primitive this item establishes for the widget.
- Reworking `20-09`'s own chat-originated gate — untouched, already shipped.
- A shared `Ago.Platform.*` verification package — named above as premature with only two consumers.

## Done when

- [ ] A first-time visitor with no prior verified phone can complete a real booking through the public
      widget end to end, including a real (or honestly-unverified-live, per the gap above) SMS/voice
      code round trip.
- [ ] A returning customer whose phone is already verified from an earlier chat-originated booking is
      not asked to re-verify, if (b) is built — proven by a test.
- [ ] `BookEventRequest`'s new field(s) cannot be used to self-assert verification without the real
      mechanism actually running — proven by a test that a forged/missing assertion is refused the same
      way `20-09`'s own chat-side gate refuses one.
- [ ] The chosen shape ((a)/(b)/(c), or a combination) is recorded in this file with its own reasoning,
      before the rest of Scope is built against it.

## Open questions

- Whether a shared SMS/voice gateway account across `ago-chat` and `ago-calendar` (if (c) is chosen) is
  a deployment-config decision the operator makes once, or something this item's own code needs to
  anticipate two independently-configured accounts for — decide when the vendor question `14-15` itself
  left open is finally answered, since the answer likely constrains this one.
