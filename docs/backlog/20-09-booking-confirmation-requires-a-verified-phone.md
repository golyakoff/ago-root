# Booking confirmation requires a verified phone, plus prioritized additional channels

- **Stage**: 20 (and 14 — the verification mechanism it consumes lives there)
- **Status**: ready
- **Depends on**: `14-15-phone-verification-via-call-or-sms-code.md` — this item is that primitive's
  first real consumer, and cannot be built before it. `20-07-calendar-becomes-a-chat-module.md` (done) —
  the chat-originated booking flow this item's own trigger scenario describes. `20-04-confirmation-sweep-and-operator-queue.md`
  (done) — this item changes that sweep's own batch-claim query; see "The polarity conflict" below before
  assuming it is additive only. `20-08-who-confirms-a-booking-that-started-in-a-conversation.md`
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
a **verified** qualifier to a field that already exists, rather than inventing a new one. That makes the
natural home for the rule "`Event.Confirm(now)` may not fire without it" the booking state machine
itself (`Event.Status ∈ {Available, PendingConfirmation, Booked, ...}`, `20-01`) — specifically the
`PendingConfirmation → Booked` transition, the point of no return `20-01`'s own confirmation-sweep job
(`20-04`) otherwise reaches on a timer. This lives in Calendar regardless of which surface created the
booking — the chat-originated flow this item's own trigger scenario describes, and (if this deployment
ever ships one) a booking widget with no chat conversation behind it at all. Scoping this to
"chat-originated bookings only" would leave a second, un-gated path to `Booked` the moment one exists —
decide explicitly whether the rule is universal (recommended, named as the default below) or chat-only,
and record which, rather than let the two paths silently diverge.

## The polarity conflict with `20-04`'s own sweep, named because it is load-bearing

`20-04`'s confirmation-sweep job confirms **by default**: a `PendingConfirmation` event that nobody
touches before its `ConfirmationDeadline` is automatically flipped to `Booked` on a timer — the sweep
exists precisely so a booking does not need anyone to act on it to succeed. This item needs the opposite
polarity for a booking with no verified phone: **denied by default**, requiring an affirmative action
(the code coming back correct) before `Booked` becomes reachable at all.

Left unreconciled, the sweep would simply confirm every unverified booking anyway once its deadline
passed, making this item's whole guarantee a formality that holds only until the timer fires — the
failure mode named right in this item's own "Where this came from" section (a booking with no real way
to reach the person, indistinguishable at `Booked` from one that does). The sweep's own batch-claim query
(`WHERE status = 'PendingConfirmation' AND confirmation_deadline < now()`, `20-04`'s own shape) has to
exclude rows still waiting on this item's own verification, or reach a different outcome than `Booked`
for them — expire back to `Available` (loses the slot; matches `ConfirmationDeadline`'s existing "nobody
acted in time" reasoning, now covering "acted but did not prove the phone" too) or route to the operator
queue as a **verification-failed** case distinct from the ordinary pending queue (keeps the slot, costs
an operator's attention) — neither chosen here; record which, and change `20-04`'s own sweep query
accordingly rather than adding a check only to whichever path this item's own author writes first and
missing the one that already exists.

## Relation to `20-08`

Different axis, cross-referenced deliberately. `20-08` asks **who is authorized to act** on a booking
card from inside a chat conversation (an operator-identity question). This item asks **what must be true
of the booking itself** before it can be confirmed at all (a data-integrity/trust question), independent
of who is doing the confirming. A booking gated by this item's rule but authorized by whatever `20-08`
eventually decides are two independent checks that both have to pass — neither substitutes for the
other.

## The cross-product data question, named rather than resolved

A verified phone's evidence (the `ChannelIdentity` `14-15` produces) lives in `Ago.Chat`'s own database.
`customers`/`Event` live in `Ago.Calendar`'s own, separate database, in a separate repository —
`adr/0027`'s own boundary, upheld everywhere else in this codebase. This item cannot simply join across
that boundary at confirmation time. Two real shapes to weigh, neither chosen here:

- **Calendar trusts a signed claim from Chat at confirmation time** — Chat calls Calendar's own booking-
  confirm endpoint (or the reverse, Calendar calls a small "is this phone verified for this visitor"
  query into Chat) carrying proof, verified once, at the moment it matters. Keeps `customers.phone`
  itself free of a foreign trust dependency after the fact, at the cost of a live cross-repository call
  on the confirmation path (`20-07`'s own wire-contract precedent for the shape such a call would take).
- **The verification result is snapshotted onto the booking/customer row at confirmation time** — a
  `phone_verified_at` timestamp (and, for the priority-list want below, a small ordered snapshot of
  channel kind + address, not a live reference). Simpler, no live cross-repository dependency once
  confirmed, at the cost of the two systems' own records being able to drift silently (Chat later
  unlinking the identity does not retroactively un-verify an already-confirmed booking) — decide whether
  that drift is acceptable (probably yes: the booking already happened) or needs its own reconciliation.

Whichever is chosen, apply the identical shape to the priority-ordered additional-channels want, rather
than inventing a second data-flow pattern for it.

## Scope

- The Calendar-side gate itself: `Event.Confirm(now)` (the `PendingConfirmation → Booked` transition,
  `20-01`) refuses without a verified phone, proven by a test that an otherwise-valid confirmation
  attempt with no verification evidence is rejected.
- **`20-04`'s own sweep query changed to match**, per the polarity conflict above — its own
  expired-and-unactioned batch-claim either excludes still-unverified rows (routing them to whichever of
  the two fates that section names, decided and recorded) or the sweep gains its own verified-phone
  check mirroring the explicit-confirm path's — proven by a test that an expired, unverified
  `PendingConfirmation` row does **not** reach `Booked` through the sweep, the specific failure this
  item exists to close.
- The chat-side trigger: at the point `20-07`'s own module flow reaches an agreed time, a step that asks
  for phone verification (reusing `14-15`'s own send/confirm flow) before the booking task itself reports
  complete — the concrete "a popup asks to confirm the phone" moment from the customer conversation.
- **Additional channels, each independently verified**: a visitor may offer more than one contact
  channel for this booking specifically, each proven the same way the phone is (`14-15` for another
  phone number, `14-12`'s existing mechanism for a messenger channel), in a priority order the visitor
  sets — proven by a test that an *unverified* additional channel is refused a place in the list, the
  same "claiming is not proof" rule this item's own primary requirement already enforces for the phone.
- Recording the chosen cross-product data shape from the section above, in this item's own file, before
  building against it.

## Out of scope

- The actual reminder-sending mechanism that would use the priority-ordered channel list — `14-03`/
  `20-05` are both `won't build` today; this item only builds and verifies the list, not a consumer of
  it. Revisit once either reminder-delivery item is picked back up.
- Retroactively verifying a phone on a booking that already reached `Booked` before this item ships — no
  backfill; this item's rule applies going forward only, stated explicitly so nobody assumes existing
  data was silently upgraded.
- The `20-08` authorization question — named above as a different axis, not decided or touched here.

## Done when

- [ ] A booking cannot reach `Booked` via `Event.Confirm(now)` without a verified phone, proven by a
      test that an otherwise-valid confirmation is refused without one.
- [ ] `20-04`'s own sweep cannot reach `Booked` for an unverified booking either, proven by a test that
      an expired, unverified `PendingConfirmation` row is excluded from the sweep's batch-claim (or
      routed to the chosen alternate fate, not silently confirmed) — the polarity-conflict fix, not just
      the explicit-confirm-path check above.
- [ ] The chat-originated flow (`20-07`) actually prompts for and completes phone verification
      (`14-15`) as part of reaching `Booked`, proven end to end through the real module task flow, not
      by inspection.
- [ ] A visitor can add additional contact channels for a specific booking, each refused a place in the
      priority list until independently verified, proven by a test per channel kind exercised.
- [ ] The cross-product data shape (live cross-repository check vs. snapshot at confirmation time) is
      recorded in this file, with the reasoning for the choice, before the rest of the scope is built.
- [ ] Whether the rule is universal across every booking-creation surface or chat-originated-only is
      recorded explicitly, per "Why this is a Calendar-side rule" above.

## Open questions

- Whether a booking with a phone verification that never completes (visitor abandons the flow) should
  time out back to an earlier `Event.Status`, freeing the slot, or hold it briefly pending a retry — a
  real UX/inventory tradeoff `20-01`'s own state machine did not anticipate needing to answer.
- Interaction with `14-13`'s own visitor-wide preferred channel: whether this item's own per-booking
  priority list overrides it for booking-related messages specifically, or the two are meant to be the
  same list read two different ways — decide before both exist and quietly disagree.
