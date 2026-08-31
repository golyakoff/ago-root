# Phone verification via a proactive call or SMS code

- **Stage**: 14
- **Status**: built (2026-08-31, `ago-chat#143`, not yet merged) — no live gateway account exists in
  this environment; see the "Live-verification gap" note on the first Done-when box
- **Depends on**: `adr/0079-verified-channel-identity-linking-and-a-preferred-reply-channel.md` — the
  verification-by-evidence principle this item extends to a channel class that cannot supply the
  evidence `14-12` relies on. `14-12-verified-channel-identity-linking.md` (done) — this item's own
  output is a `ChannelIdentity`, not a parallel concept; see "Why not a parallel concept" below.
  `14-14-unverified-contact-details.md` (done) — the phone number this item verifies typically starts
  life as one of these, hand-typed by an operator or a visitor.

## Goal

A visitor's phone number moves from "a fact someone typed" to "a number this system has proven that
visitor can currently answer or read" — by proactively calling or texting a one-time code to it and
requiring the code back, correct and inside a short window.

## Why this cannot reuse `14-12`'s mechanism

`14-12`'s verification is evidence-based on an **inbound** message: the visitor already has a channel
(Telegram, MAX) capable of messaging this system first, and a real message from it, matching a pending
code, is the proof. `adr/0079` explicitly rejected the opposite direction — this system messaging the
channel *first* — because Telegram/MAX/WhatsApp bot policy refuses unsolicited contact with an address
that has not messaged the bot yet.

A bare phone number has no such channel. Nothing here has ever messaged this system; there is no bot
account to be blocked from starting the conversation. Proving control is only possible in the direction
`14-12` ruled out for chat channels — **this system must call or text first**, which is not a policy
violation for SMS/PSTN (there is no bot-relationship concept to violate) but is a real cost this item's
own Open questions section has to name honestly.

## Why not a parallel "verified phone" concept

Once a code is confirmed, the correct outcome is a real `ChannelIdentity` — the same aggregate `14-12`
already built, `14-13` already reads for the preferred-channel fallback, and `14-14` already
distinguishes itself from. Inventing a second "verified phone" table alongside it would mean every
consumer of verification status (the preferred-channel logic, a future booking-confirmation gate, the
console's own display) has to know about two trust stores instead of one. This item's own scope is
therefore "produce the evidence `ChannelIdentity.Link` already knows how to consume," not "build a new
kind of trust."

The one real difference from `14-12`'s own flow: `ChannelKind` gains no new member for this (`Sms`
already exists in `ChannelKind`, unused since `14-03`'s own SMS *channel adapter* — full two-way
messaging — is `won't build`). This item is narrower than a channel adapter: it only ever sends one
templated code and reads back a match, never arbitrary inbound/outbound message traffic. Confirm before
building whether `ChannelKind.Sms` can be reused for a `ChannelIdentity` this narrow, or whether reusing
it would misrepresent the identity as "this site can message this visitor over SMS generally," which it
cannot — record the answer, don't assume it.

**Decided: `ChannelKind.Sms` is reused**, for the resulting identity regardless of whether the code was
delivered by SMS text or a voice call. The fact this identity records is "this phone number is reachable
by this visitor" — a PSTN address — not "which wire carried the six digits", so a second enum member
distinguishing delivery method would misrepresent capability in the opposite direction: it would suggest
two different "channels" exist for one phone number depending on how it happened to be verified.
Concretely safe today because `InboundChannelAdapterRegistry` has no adapter registered for
`ChannelKind.Sms` (`14-03` is `won't build`), so `DeliverChannelMessageHandler` already degrades a
resolved-but-unadapted channel to its existing "no adapter for this channel" outcome for any identity of
this kind — the identical graceful path any other unbuilt-adapter channel identity already hits, not a
new failure mode this item introduces.

## Scope

- A new port, `IPhoneVerificationSender` (or the name a fuller design settles on), with two operations:
  initiate a code send to a phone number over a chosen channel (SMS text, or a voice call reading digits
  aloud), and confirm a submitted code against the pending request.

  **Shipped as visitor-only** (both initiate and confirm) — no operator-relay entry point. The code is
  read off a call or an SMS arriving on the visitor's own phone, so the visitor is the only party who can
  meaningfully act on either half of this flow; unlike `CreateAttachment`/`RecordVisitorContactDetail`,
  there is no analogous action an operator genuinely performs themselves here. An operator-relay path (an
  operator typing the number, or the code, on the visitor's behalf) is a small, additive follow-up if a
  real workflow ever asks for it — deliberately left out to avoid an unused second path.
- A small pending-verification aggregate: phone number, hashed code (never store the code in clear —
  the same reasoning a password hash gets, since a phone in front of an attacker plus a leaked plaintext
  code is a full bypass), delivery channel used, expiry, attempt count.
- **Lockout, not just expiry**: a bounded number of wrong-code attempts before the pending request is
  refused outright and a new one is required — proven by a test, the same defense-in-depth
  `visitor-sessions`' own rate limiting already applies elsewhere in this codebase.
- **Abuse/cost protection on the send side**, separate from the confirm-side lockout above: initiating a
  send costs real money per attempt (SMS/voice both bill per message/minute), so a limiter on how many
  sends one phone number — and one visitor/IP, to catch someone iterating through numbers — can trigger
  in a window. `20-03`'s own phone-keyed Redis rate-limit bucket is the closest existing precedent to
  confirm reusability against, not necessarily to reuse verbatim (that bucket protects a booking
  endpoint's own write, not a paid external send).
- On a confirmed code: create (or reuse, if one already exists and is merely unverified) the visitor's
  `ChannelIdentity` for this phone number, through the identical `Link` mutation `14-12` already built —
  proven by a test that a second verification of the same number does not create a duplicate identity.
- The vendor/gateway decision, researched and recorded — see Open questions; this item's own Done-when
  does not require the account to exist, only the decision and the port shape to be real.

## Out of scope

- Automatic phone-number extraction from message text — `14-14`'s own out-of-scope reasoning applies
  identically here; a number only enters this item's flow because a visitor or operator explicitly
  offered it for verification.
- Verifying anything other than a phone number — email, and any other unverifiable-today channel from
  `14-14`'s own list, are a separate future item if ever justified.
- Gating anything on the result. This item produces a verified `ChannelIdentity`; **what** requires one
  (a booking confirmation, most immediately) is a separate item — see `20-09`.
- A live account with a real SMS/voice gateway — the same "decide and record, provision later"
  discipline `10-05` already established for transactional email.

## Done when

- [x] A code can be sent to a real phone number over at least one of SMS or voice call, and the exact
      live-verification gap is stated plainly if it cannot be proven end to end in this environment (no
      real gateway account exists here today — name that honestly rather than asserting success by
      inspection, the same discipline `14-08`/`14-10`/`14-11` already held themselves to for their own
      unverified live accounts). **The mechanism is real and proven against an in-process stand-in
      (`UnconfiguredPhoneVerificationSender`, unit-tested); no live send to a real phone was ever
      attempted — the identical unverified-live-channel gap `14-08`/`14-10`/`14-11` already carry, named
      here rather than asserted away.**
- [x] Confirming the correct code within the expiry window produces a real `ChannelIdentity`, reusing
      `14-12`'s own `Link` mutation — proven by a test, not by inspection.
- [x] A wrong code, an expired code, and a locked-out phone (too many wrong attempts) are each refused,
      proven by a test per case.
- [x] A send-side rate limit exists and is proven by a test that a phone number (or visitor/IP) past the
      limit is refused a new send rather than silently billed again.
- [x] The vendor/gateway decision is recorded, even if the recorded answer is "undecided, needs a cost
      quote before commit" — an honest open decision beats an invented number. **Recorded: undecided, see
      Open questions below.**

## Open questions

- **SMS vs. voice call as the default**, or made configurable per site/tenant. The author's own current
  lean is voice, for cost — but SMS is the channel a person reliably *sees* (a chat/bot message can sit
  unread; an SMS notification does not, in the author's own stated experience), which matters more for
  a later reminder use case than for a one-time verification code read once. Note this tension rather
  than resolving it here: `14-03` (SMS channel adapter) and `20-05` (SMS booking-confirmation delivery)
  are both `won't build` today for cost/priority reasons unrelated to verification — if either is
  revisited, this item's own SMS-vs-voice choice should be revisited alongside it, not independently.

  **Decided: SMS is the default** (`PhoneVerificationOptions.DefaultDeliveryMethod`, a deployment-wide
  setting, not yet per-site — no caller needs a per-site override today). Reasoning: this is a one-shot
  verification code with a short validity window (10 minutes), not a recurring reminder — the use case
  where voice's cost advantage would matter most (repeated sends) does not apply here. What does apply is
  the tension the author's own note names in the other direction: a code that sits unread past its short
  window is a failed verification, and SMS is the channel more reliably *seen* in that same short window.
  The cost difference between one SMS and one voice call, for a single one-time code, is real but smaller
  than the cost of a verification that silently fails because the visitor did not notice a missed call.
  This is a reasoned default, not a measured one — no comparative delivery-success data exists for either
  channel in this codebase yet. The port (`IPhoneVerificationSender`) takes the delivery method as a
  parameter regardless, so nothing about this default is structural; flipping it, or making it
  configurable per site, is a one-line change whenever real data says otherwise.

- **Which gateway** — unresearched. The same category of decision `20-05`/`14-03` already left open for
  outbound SMS; a voice-call OTP provider has not been researched here at all. Needs a real comparison
  (coverage of Russian mobile numbers, per-call/per-SMS cost, whether a single vendor can do both) before
  committing a package or an HTTP integration.

  **Still undecided — no vendor was researched for this implementation.** No live account exists in this
  environment, the same honestly-stated gap `14-08`/`14-10`/`14-11` already carry for their own
  unverified live channels. What was built instead is the pluggable shape the eventual choice slots into
  without a redesign: `IPhoneVerificationSender` (provider-neutral port, in `Ago.Chat.Application`),
  `UnconfiguredPhoneVerificationSender` (what is actually registered today — throws a loud, dead-letterable
  refusal rather than silently dropping a code), and `ResilientPhoneVerificationSender` plus
  `PhoneVerificationResiliencePipeline` (the retry/circuit-breaker/timeout wrapping a real gateway client
  would need, built and unit-tested against a stub, not wired to anything real). A real
  `Ago.Chat.Infrastructure.<Vendor>` client is a same-shaped addition the day an account and a cost quote
  exist — no change to `Ago.Chat.Application`, `Ago.Chat.Worker`, or the API surface.

- **Whether a freshly verified phone becomes the visitor's `14-13` preferred channel automatically**, or
  requires an explicit choice — `14-13`'s own file does not anticipate a channel arriving through
  verification-that-was-triggered-by-a-booking-flow rather than an operator/visitor deliberately linking
  one; decide when `20-09` is scoped in detail, since that is the item that will actually trigger this
  flow in practice.

  **Left open, as directed** — out of this item's own scope; `20-09` decides it.
