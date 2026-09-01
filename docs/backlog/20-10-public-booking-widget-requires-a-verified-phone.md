# Public booking widget requires a verified phone

- **Stage**: 20 (and 14 — likely consumes or mirrors a `14-15`-shaped mechanism)
- **Status**: ready
- **Depends on**: `20-09-booking-confirmation-requires-a-verified-phone.md` (built, chat-only) — this
  item is the named follow-up its own Outcome section points to, extending the identical guarantee to
  the one calling surface `20-09` deliberately left untouched. `14-15-phone-verification-via-call-or-sms-code.md`
  (done) — the confirm-side domain logic this item's own aggregate mirrors, not calls; see "Decided"
  below for the shape and why no vendor account is this item's own blocker.

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

## Decided (2026-09-01): (c), with (b) alongside it — and a real answer to (c)'s own cost objection

(c)'s stated cost above was "a second real cost" — a second SMS/voice gateway account, paid, before
this item can even be demonstrated. **That cost is deferred, not paid, by splitting what "verified"
actually requires the same way `14-15` already split it and this item's own "What already exists"
section above already names**: sending a code is one port (`IPhoneVerificationSender`-shaped, provider-
neutral, no vendor name in `Application`); confirming one is plain domain logic — comparing a submitted
code's hash against the stored one, with lockout and expiry — and was **never behind a port in `14-15`
either**, so there is nothing here to fake in the first place. Only the sending side can be substituted.

**`Ago.Calendar.Module` registers a `FakePhoneVerificationSender` as `Ago.Calendar`'s own
`IPhoneVerificationSender` by default — not `ago-chat`'s `UnconfiguredPhoneVerificationSender`-shaped
"throw, this is not configured," a genuinely different choice made deliberately.** `14-15`'s own sender
throws because nothing in that item's scope needed a working end-to-end demo before a vendor was
chosen — the honest gap was named and left open. This item's whole point is a real, live, first-time
visitor completing a real booking through the public widget, and that cannot be demonstrated at all
behind a sender that refuses every call. So `FakePhoneVerificationSender` does not fake the
verification — it fakes exactly one real-world side effect: no SMS is actually sent. The code is real,
generated, hashed and stored the same way `14-15`'s own `PendingPhoneVerification` does it; the fake
sender's only job is to make that real code visible somewhere a person or a test can read it (a
structured log line at minimum; the live demo may additionally want it surfaced through
`ConsoleEndpoints.cs`'s existing dev-provisioning precedent, decided at implementation) instead of
placing a call that would cost money and requires an account that does not exist. **This is what
`14-15` itself was never able to reach — a real, live, end-to-end demonstrable flow, with the one
honestly-named gap being narrower than `14-15`'s own** (no live *gateway delivery*, but a fully live
verification mechanism, exercisable today on the demo cluster with zero new spend).

**The swap point for a real vendor, later, is unchanged from `14-15`'s own precedent**: a concrete
`Ago.Calendar.Infrastructure.<Vendor>.<Vendor>PhoneVerificationSenderClient` implements the identical
port and replaces the DI registration — nothing in `Application`/`Domain`/the confirm handler moves.

## Scope

- Calendar's own phone-verification primitive, structurally mirroring `14-15`: a pending-verification
  aggregate (code hash, expiry, attempt count/lockout), `IPhoneVerificationSender` as its own
  Application-layer port, and `FakePhoneVerificationSender` as the one implementation this item ships
  with — decided above, and the reason a real vendor account is not this item's own blocker.
- Wired into `BookingEndpoints.cs`'s own request handling — `BookEventRequest` gains a verification
  token/code field the confirm step produced, following the identical shape `14-15`'s own confirm
  handler already established (not reinvented here).
- `BookEvent.RequiresVerifiedPhone` set `true` for this endpoint once the mechanism exists — the one
  line `20-09` deliberately left as `false`, becoming `true` is this item's own actual "done" signal at
  the code level.
- (b), built alongside (c) as decided above: the endpoint checks `customers.phone_verified_at` for a
  match on the asserted phone before requiring a fresh verification round — a cheap, real improvement
  for a repeat customer, and it costs nothing extra to include since the column already exists.
- **What is still an honestly-named gap, and smaller than `14-15`'s own**: no real SMS/voice gateway
  delivers a code to a real phone. Everything else — the pending aggregate, the hash/lockout/expiry
  logic, the confirm handler, the widget's own round trip — is real and is exercised live, including on
  the demo cluster, through the fake sender. When a real vendor account exists, only the DI
  registration and one new Infrastructure client change.

## Out of scope

- `20-11`'s own additional-channels scope — a different item, though likely built on the same
  verification primitive this item establishes for the widget.
- Reworking `20-09`'s own chat-originated gate — untouched, already shipped.
- A shared `Ago.Platform.*` verification package — named above as premature with only two consumers.

## Done when

- [ ] A first-time visitor with no prior verified phone completes a real booking through the public
      widget end to end — a real code is generated, hashed, stored, retrieved (via the fake sender's
      log/dev surface), submitted and confirmed — proven live against the demo cluster, not merely by
      inspection. The only honestly-named gap is that no real SMS/voice call is placed, per the Scope
      section above.
- [ ] A wrong code is refused, a code is locked out after too many wrong attempts, and an expired code
      is refused — the same guarantees `14-15`'s own domain logic already proves, proven again here
      since this is a second aggregate, not a shared one.
- [ ] A returning customer whose phone is already verified from an earlier chat-originated booking is
      not asked to re-verify — proven by a test.
- [ ] `BookEventRequest`'s new field(s) cannot be used to self-assert verification without the real
      confirm mechanism actually having run — proven by a test that a forged/missing token is refused
      the same way `20-09`'s own chat-side gate refuses one.
- [ ] `FakePhoneVerificationSender` is the only sender registered; nothing in this item's own code path
      can silently reach a real gateway that was never actually configured.

## Open questions

- Whether a shared SMS/voice gateway account across `ago-chat` and `ago-calendar` is a deployment-config
  decision the operator makes once, or something this item's own code needs to anticipate two
  independently-configured accounts for — decide when the vendor question `14-15` itself left open is
  finally answered (`ago-business#31`'s own comparison is what that decision waits on), since the answer
  likely constrains this one. Not a blocker for this item itself: `FakePhoneVerificationSender` needs no
  vendor decision at all.
- Where the fake sender surfaces the code for a human to read on the live demo cluster specifically — a
  structured log line is the floor and is enough for the automated Done-when tests above; whether the
  demo also wants it echoed through an existing dev-only surface (`ConsoleEndpoints.cs`'s provisioning
  precedent) for a person to click through the flow by hand is a nice-to-have, decide at implementation.
