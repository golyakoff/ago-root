# Public booking widget requires a verified phone

- **Stage**: 20 (and 14 — likely consumes or mirrors a `14-15`-shaped mechanism)
- **Status**: done (`ago-calendar#19`, merged 2026-09-01) — see Outcome below
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

- [x] A first-time visitor with no prior verified phone completes a real booking through the public
      widget end to end — a real code is generated, hashed, stored, retrieved (via the fake sender's
      log/dev surface), submitted and confirmed — proven via real HTTP + real Postgres integration
      tests, not merely by inspection. The only honestly-named gap is that no real SMS/voice call is
      placed, per the Scope section above (see Outcome for one further, real gap found).
- [x] A wrong code is refused, a code is locked out after too many wrong attempts, and an expired code
      is refused — the same guarantees `14-15`'s own domain logic already proves, proven again here
      since this is a second aggregate, not a shared one.
- [x] A returning customer whose phone is already verified from an earlier chat-originated booking is
      not asked to re-verify — proven by a test.
- [x] `BookEventRequest`'s new field(s) cannot be used to self-assert verification without the real
      confirm mechanism actually having run — proven by a test that a forged/missing token is refused
      the same way `20-09`'s own chat-side gate refuses one.
- [x] `FakePhoneVerificationSender` is the only sender registered; nothing in this item's own code path
      can silently reach a real gateway that was never actually configured.

## Outcome

Built and merged 2026-09-01 (`ago-calendar#19`). Independently re-verified by the managing session:
511/511 (Domain 181, Application 130, Architecture 18, Concurrency 19, Integration 163), `dotnet
format`/build clean, zero warnings. Fails-before independently re-proven for the property this item's
own file names as the critical one — a caller must not be able to verify phone A and then book with
phone B using the same token: neutralised the phone comparison in
`PendingPhoneVerification.IsProofValid`, confirmed `ACorrectProofToken_ForADifferentPhoneNumber_IsRejected`
failed (a token confirmed for one phone was accepted for booking a different one), restored, full suite
re-confirmed green.

**Fake-sender surface, decided**: a structured `Information` log line is the floor (satisfies the
automated tests), plus a small dev-only endpoint (`!IsProduction()`-gated, mirroring
`DevProvisioningEndpoints.cs`'s own precedent) so a person can click through the flow on the demo
cluster by hand.

**Rate-limit buckets, decided**: phone (harassment, checked first), calling IP (this endpoint has no
session/visitor concept the way chat does, so IP substitutes), calendar (coarse flood bound) — both
phone and IP hashed before use as Redis keys, matching `BookEventHandler.PhoneBucket`'s own existing
personal-data discipline.

**Token/proof shape, decided**: a fresh opaque bearer token (32 random bytes, base64url,
`phvfy_`-prefixed, matching `ago-chat`'s own `WebhookSecretGenerator` shape) minted only on a
`Confirmed` outcome, hashed before storage, returned once in plaintext. `BookEventRequest` carries
`{PhoneVerificationId, PhoneVerificationProofToken}`.

**A doc correction owed and made in the same change**: `docs/architecture/personal-data.md` never
carried a row for this new store. Added below.

## Correction, 2026-09-01: this item's own title is misleading — there is no widget caller

Written into the file the same day the gap was found, before dispatching any further work against a
wrong premise.

At the time this item was scoped, "the public booking widget" was assumed to mean a browser module
inside `ago-widget` that talks to `Ago.Calendar.Api` directly, and the endpoint this item gates
(`POST /calendars/{id}/events/{id}/book`) was assumed to be that module's own call. **That assumption
predates `20-07`.** `20-07` (Calendar becomes a chat module, done 2026-08-29) deleted `ago-widget`'s
entire direct HTTP client to Calendar — `calendarClient.ts`, `flow.ts`, `panel.ts`, all of it — and
replaced it with the booking flow running *through the conversation*, as ordinary chat messages. The
surviving `src/modules/booking/chip.ts` says so in its own doc comment, in as many words: "There is no
direct network call to AGO Calendar left anywhere in this repository, base bundle or lazy module
alike." `20-06`'s own file independently confirms the same decision from the other direction ("no
second widget and no second script tag"; every booking, from every channel, is reached through the
conversation).

**Consequence, checked directly rather than assumed**: nothing in `ago-widget` calls, or will ever
call, the endpoint this item gates. The guarantee this item built is real and correctly implemented —
the code review above stands — but its own premise ("a public, embeddable booking widget that cannot
complete a booking at all") was already stale by the time this item was written, because that widget
path had already been deleted five days earlier by `20-07`.

**So who does call the public endpoint? Revisited by the author, 2026-09-01, same day: nobody, and
that is the honest answer, not a placeholder for one.** A third-party-integrator reading was proposed
first and briefly recorded here; the author reconsidered it the same day and could not construct a real
case where a tenant would integrate directly against Calendar's own API rather than through the chat
widget every other product decision already routes bookings through. `20-19` (a documentation/reference
item built on the third-party premise) is **withdrawn** — see that file's own note.

**What this leaves standing**: `Ago.Calendar.Api`'s public `POST /calendars/{id}/events/{id}/book`
endpoint, and the phone-verification gate this item built in front of it, currently have **no real
caller in any product combination the author can presently justify**. The guarantee itself is real,
correctly implemented, and independently verified (see Outcome above) — this is not a defect in what
was built, and nothing here proposes removing tested code on a guess. It is a fact worth recording
plainly rather than papering over with an invented consumer: this item's own done-when was satisfied at
the wire-contract level, against a caller that turns out not to exist yet. Whether the endpoint should
stay as dormant, defensible infrastructure for a future integration surface, or whether it is worth
retiring, is a separate decision the author has not made and this item does not make for them.

## Open questions

None outstanding — resolved during implementation; see Outcome above. The vendor-account question
(shared across `ago-chat`/`ago-calendar` or independent) remains genuinely open but is not a blocker for
anything this item built — `FakePhoneVerificationSender` needs no vendor decision at all, and the swap
point for a real client is unchanged and documented in `IPhoneVerificationSender`'s own remarks.
