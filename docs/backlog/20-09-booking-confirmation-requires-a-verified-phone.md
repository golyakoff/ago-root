# Booking confirmation requires a verified phone, plus prioritized additional channels

- **Stage**: 20 (and 14 — the verification mechanism it consumes lives there)
- **Status**: done, chat-only (`ago-chat#144`, `ago-calendar#12`, merged 2026-08-31) — see
  Outcome below; the public booking widget is out of this item's own scope, covered instead by
  `20-10-public-booking-widget-requires-a-verified-phone.md`
- **Depends on**: `14-15-phone-verification-via-call-or-sms-code.md` — this item is that primitive's
  first real consumer, and cannot be built before it. `20-07-calendar-becomes-a-chat-module.md` (done) —
  the chat-originated booking flow this item's own trigger scenario describes, and the flow that must
  sequence `14-15` before its own claim call. `20-04-confirmation-sweep-and-operator-queue.md` (done) —
  **deliberately untouched by this item**, per "Decided 2026-08-31" below; named here so nobody assumes
  a change is needed and goes looking for one. `20-08-who-confirms-a-booking-that-started-in-a-conversation.md`
  (blocked on `20-07`, unrelated axis — see below) — both items are about "confirming a booking," from
  different directions; cross-reference, do not conflate.

## Where this came from

Raised 2026-08-30 in a conversation with a prospective real customer, not invented speculatively. The
concrete scenario: a visitor books a slot through a chat conversation (`20-07`'s own module flow); once
a time is agreed, a popup asks the visitor to confirm their phone number — a code is sent by SMS or
voice call, the visitor enters it back, and only then does the booking actually confirm. The customer's
own reasoning, restated: a booking with no verified way to reach the person behind it is worth much less
than one that does — a no-show, or a booking made to grief the calendar, costs real slots either way,
and today nothing stops either.

The same conversation named a second, related want: a visitor can offer additional contact channels
beyond the phone (another number, an email, a messenger), ranked in priority order, for reminders and
booking-related messages — but **each additional channel must independently prove ownership** the same
way the phone does. A visitor typing "this is my email" is not evidence; `14-14`'s own file already
draws this exact line for a different reason (an operator-recorded, admittedly-unverified note) and this
item's own requirement is the mirror of it applied to a visitor-supplied, must-be-trusted channel.

## Why this is a Calendar-side rule, not a Chat-side one

`customers.phone` (`20-01`) is already Calendar's one mandatory field for any booking — this item adds
a **verified** qualifier to a field that already exists, rather than inventing a new one. This lives in
Calendar regardless of which surface created the booking — the chat-originated flow this item's own
trigger scenario describes, and (if this deployment ever ships one) a booking widget with no chat
conversation behind it at all. Scoping this to "chat-originated bookings only" leaves a second, un-gated
path open — named honestly below, not silently left to diverge.

**Decided: chat-only, reversing this section's own earlier "universal, recommended" framing.** The
first implementation attempt built the gate universally and found the real cost of that choice, not
just its theoretical existence: the public booking widget's own `/book` endpoint is unauthenticated and
browser-reachable, so making the gate universal without first building a *secure* way for that endpoint
to supply a verification assertion meant either a self-asserted field any caller could forge (rejected
outright as a real hole) or a widget that can no longer complete any booking at all (the shape actually
built and tested, then reverted). Narrowed to chat-only after review: `BookEvent` gained a
`RequiresVerifiedPhone` flag, `true` only from the chat-module flow — the public widget is functionally
unaffected by this item, proven by its own pre-existing tests staying byte-identical. The public
widget's own path to the same guarantee is `20-10`, a named, separate follow-up — not a hypothetical
someday, but a real prerequisite named by the author as needed before this product's first live
customer, tracked in the Now queue at the same priority as this item.

## Correction: `Event.Claim` is never called in production code, `IBookingStore.TryBookAsync` is

Every mention of `Event.Claim(...)` below is shorthand for "the claim operation," not a literal call
site — checked against the real `ago-calendar` code before scoping this further. `20-03`'s own real
implementation (`Ago.Calendar.Infrastructure.Postgres/BookingStore.cs`) never loads the `Event` aggregate
and calls its `Claim` method in application code; the claim is a single atomic `UPDATE events SET
status = 'PendingConfirmation', customer_id = @customerId, ... WHERE id = @eventId AND status =
'Available' AND starts_at > @now` (`BookingStore.ClaimSlotSql`), inside the same transaction as
`UpsertCustomerAsync` (the phone-keyed customer upsert), both called from `IBookingStore.TryBookAsync`.
`Event.Claim`'s own C# method exists in `Ago.Calendar.Domain/Event.cs` as the precondition's canonical
statement (and is what unit tests exercise), but the SQL statement is what actually runs in production —
`ClaimSlotSql`'s own doc comment states this explicitly ("checked in application code it would be
checked against a reading of the row from milliseconds ago").

**This changes where this item's own gate has to live**: not "add a check before a C# method call," but
"add the verified-phone condition to the same atomic SQL statement, or a companion check inside the same
transaction" — the identical reasoning that put the `status = 'Available'`/`starts_at > @now` checks in
the `WHERE` clause rather than in application code applies here too. Whoever implements this decides the
exact SQL shape (an added `WHERE` condition reading a value already present on the `customers` upsert, a
second `UPDATE` in the same transaction, or something else) and records it — this file only establishes
that "gate `Event.Claim`" means gating `TryBookAsync`'s real SQL path, not the domain method.

## Decided 2026-08-31: verify before claiming, not before confirming — the sweep is untouched

An earlier draft of this item gated `Event.Confirm(now)` (the `PendingConfirmation → Booked`
transition) on a verified phone, and found a real, load-bearing conflict there: `20-04`'s own
confirmation-sweep job confirms **by default** — a `PendingConfirmation` event nobody touches before its
`ConfirmationDeadline` is automatically flipped to `Booked` on a timer, and that sweep has no reason to
know anything about phone verification. Gating `Confirm` alone would have left the sweep silently
confirming unverified bookings the moment its own timer fired, defeating the item's own guarantee.

**Resolved by moving the gate earlier: phone verification is required *before* `Event.Claim(customerId,
now, confirmationDeadline)` is ever called** — before `Available → PendingConfirmation`, not at the
`PendingConfirmation → Booked` step. Concretely: the chat-side flow (`20-07`'s own module task) runs
`14-15`'s verification to completion first; only a successfully verified phone number becomes the
`customerId` (`20-03`'s own phone-keyed customer lead card) the claim call is made with. By construction,
every row that ever reaches `PendingConfirmation` already has a verified phone behind its `customerId` —
`20-04`'s sweep needs **no change at all**, because there is no unverified row for it to wrongly confirm.
This is a materially simpler shape than the rejected alternative, and the reason to prefer it once named:
one gate, at one call site, rather than two gates (an explicit-confirm check plus a sweep-query rewrite)
that both have to stay in sync forever.

**The honest tradeoff this creates, not present in the rejected shape**: `20-03`'s own atomic
compare-and-set claim is what currently prevents two visitors racing for the same slot, and it fires
*before* any of this — an `Available` row is only ever claimed, never held speculatively while something
else happens first. Moving verification ahead of `Claim` means the slot stays `Available`, and claimable
by someone else, for the entire verification window (a phone call can run a minute or more). A visitor
who completes verification correctly can still arrive at the claim call to find the slot gone. This is a
real, new failure mode this item introduces and must handle honestly — surfacing it as "that time is no
longer available, please pick another" rather than a generic error, and *not* attempting to hold the slot
speculatively during verification (a speculative hold reopens exactly the double-booking race `20-03`'s
own atomic claim exists to prevent, for a visitor who may never finish verifying at all).

## Relation to `20-08`

Different axis, cross-referenced deliberately. `20-08` asks **who is authorized to act** on a booking
card from inside a chat conversation (an operator-identity question). This item asks **what must be true
of the booking itself** before it can be confirmed at all (a data-integrity/trust question), independent
of who is doing the confirming. A booking gated by this item's rule but authorized by whatever `20-08`
eventually decides are two independent checks that both have to pass — neither substitutes for the
other.

## The cross-product data question, substantially simplified by the decision above

A verified phone's evidence (the `ChannelIdentity` `14-15` produces) lives in `Ago.Chat`'s own database;
`customers`/`Event` live in `Ago.Calendar`'s own, separate database, in a separate repository —
`adr/0027`'s own boundary. Gating `Claim` rather than `Confirm` means this is no longer "invent a new
cross-repository check at a new call site" — `Claim` already needs a `customerId` (`20-03`'s own
phone-keyed customer lead card), so there is already exactly one wire call, at exactly this point, that
carries a phone number across the product boundary (`20-07`'s own module wire contract, or whatever
surface calls `Claim`). The verification result rides along on that existing call rather than needing a
second one.

**Recommended, not yet built**: Calendar snapshots a `phone_verified_at` timestamp onto the `Customer`
row at claim time, trusting the value the calling side (Chat, having just run `14-15` to completion)
asserts — the identical service-to-service trust boundary `20-07`'s own module-task endpoints already
accept (`adr/0077`'s "authenticity is checked; the deeper claim is trusted" shape, restated here for a
phone instead of a module task). This does mean Chat later unlinking the `ChannelIdentity` does not
retroactively un-verify an already-claimed booking — named as acceptable, the same reasoning `14-15`'s
own file gives for the identical drift, since the booking's own claim already happened on a value that
was true at the time. Apply the identical snapshot shape to the priority-ordered additional-channels
want, rather than inventing a second data-flow pattern for it.

## Scope

- The chat-side gate: `20-07`'s own module flow, once a time is agreed, runs `14-15`'s verification to
  completion (the "a popup asks to confirm the phone" moment from the customer conversation) *before*
  calling whatever wire operation leads to `Event.Claim` — proven by a test that the claim call is never
  made until verification succeeds, and by a test that a wrong/expired code leaves the slot untouched
  (still `Available` for someone else, matching the honest tradeoff named above).
- Graceful handling of the new race the timing change introduces: a claim attempt that arrives after
  verification succeeds but finds the slot no longer `Available` surfaces as "that time is no longer
  available, pick another," not a generic error — proven by a test that simulates the slot being taken
  during the verification window.
- The `Customer` row gains `phone_verified_at` (or equivalent), written at claim time from the value the
  calling side asserts (the snapshot shape decided above) — proven by a test that a claim carrying no
  verification assertion is refused, the actual Calendar-side enforcement point (moved from `Confirm` to
  `Claim`, per the decision above; `20-04`'s own sweep needs **no code change**, and a test proving an
  already-verified `PendingConfirmation` row still sweeps to `Booked` normally is the regression guard
  for that claim).
- **Additional channels, each independently verified**: a visitor may offer more than one contact
  channel for this booking specifically, each proven the same way the phone is (`14-15` for another
  phone number, `14-12`'s existing mechanism for a messenger channel), in a priority order the visitor
  sets, snapshotted onto the booking the same way the phone is — proven by a test that an *unverified*
  additional channel is refused a place in the list.

## Out of scope

- The actual reminder-sending mechanism that would use the priority-ordered channel list — `14-03`/
  `20-05` are both `won't build` today; this item only builds and verifies the list, not a consumer of
  it. Revisit once either reminder-delivery item is picked back up.
- A speculative hold on the slot during the verification window — named and rejected above; the slot
  stays genuinely `Available` and claimable by someone else until verification succeeds and `Claim` is
  called.
- Retroactively verifying a phone on a booking that already reached `Booked` before this item ships — no
  backfill; this item's rule applies going forward only, stated explicitly so nobody assumes existing
  data was silently upgraded.
- The `20-08` authorization question — named above as a different axis, not decided or touched here.

## Done when

- [x] `IBookingStore.TryBookAsync` (the real claim mechanism, see the correction above) cannot be
      reached by the chat-originated flow without a completed `14-15` verification immediately
      preceding it, proven end to end through the real module task flow, against a real Postgres.
- [x] `20-04`'s own sweep is unmodified and still proven to confirm an (already-verified-at-claim-time)
      `PendingConfirmation` row normally — the regression guard that the decision above did not quietly
      leave a gap where the sweep's own behavior was assumed rather than re-tested.
- [x] A claim attempt that loses the slot-availability race during verification surfaces a specific,
      actionable outcome, not a generic failure — reuses the existing re-offer path a lost availability
      race already produces (`ReplyToModuleTaskHandler`'s own `ReopenForSlotChoice`), proven by a test.
- [ ] **Deferred, not built**: a visitor adding additional contact channels for a specific booking,
      priority-ordered, each independently verified. Out of this item's own delivered scope — see
      Outcome below for why, and `20-11` for where this is now tracked as its own item.
- [x] Whether the rule is universal across every booking-creation surface or chat-originated-only is
      recorded explicitly: **chat-only**, decided above, with the public widget's own path to the same
      guarantee tracked as `20-10`.

## Outcome

Built 2026-08-31 across `ago-chat` (`#144`) and `ago-calendar` (`#12`), not yet merged. Independently
re-verified by the managing session, not only reported by the implementing worker: `ago-chat` 1867/1867,
`ago-calendar` 310/310 (after the chat-only narrowing — the worker's own first pass, built universal,
scored 308/308 with the widget's own tests rewritten to expect permanent failure; narrowing back to
chat-only restored those two files to byte-identical with `main` and net +2 tests, the two the universal
pass had removed). Fails-before independently re-proven for the core gate (three tests, including two
proving the public endpoint would silently succeed without `RequiresVerifiedPhone`'s own check).

**What shipped**: a sixth Chat primitive (`VerifiedPhoneForm`), the wire-contract extension
(`RequiresVerifiedPhone`/`PhoneVerifiedAt`, additive per `api-design.md`), the Calendar-side refusal at
the real claim call site, the `phone_verified_at` snapshot (earliest-wins, matching `display_name`'s own
`COALESCE` pattern), and the sweep regression guard. Every Done-when box above is met **for the
chat-originated flow**.

**What did not ship, honestly**: additional prioritized/verified channels (deferred entirely, tracked as
`20-11`), and the public widget's own verification (never in this item's final scope, tracked as
`20-10`). Neither is a gap in this item's own delivery — both are real, separate items this Outcome
names rather than leaves implicit.

## Open questions

- What the module task does when the claim-after-verification race is actually lost (the slot went to
  someone else during the verification window): offer the visitor another slot in the same conversation
  immediately, or end the task and require restarting the booking flow from the top — a real UX question
  the timing change above introduces, not present in the rejected shape. **Resolved during
  implementation**: the existing re-offer path handles it; see Outcome above.
- Interaction with `14-13`'s own visitor-wide preferred channel: whether this item's own per-booking
  priority list overrides it for booking-related messages specifically, or the two are meant to be the
  same list read two different ways — moot until `20-11` (the deferred additional-channels scope) is
  picked up; decide there.
