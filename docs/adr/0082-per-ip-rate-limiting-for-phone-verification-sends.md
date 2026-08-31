# ADR-0082: Phone verification gets a fourth rate-limit bucket, keyed on the caller's own IP

- **Status**: Accepted
- **Date**: 2026-08-31
- **Stage**: 14 (extends `14-15`)

## Context

`14-15` (phone verification via a proactive SMS/voice code, `ago-chat`) protects
`InitiatePhoneVerificationHandler` with three rate-limit buckets — per-phone, per-visitor, per-site —
reasoned through in `PhoneVerificationRateLimitOptions`'s own remarks as covering two threats: many
attempts against *one* phone number (harassment), and one visitor iterating through *many* numbers
(enumeration). Both are real. Neither is the whole picture, and the gap was raised directly by the
account owner, in the same conversation that produced `14-15`/`20-09`: what stops a hostile third party —
named plainly as a *competitor*, not a hypothetical bad actor — from running up a shop's own SMS/voice
bill to the point of real financial harm?

**This handler is not an ordinary rate-limit target.** Every other bucket in this codebase protects
compute, storage, or a database row from being hammered — cheap to absorb, expensive only in aggregate.
`InitiatePhoneVerificationHandler` triggers a real, individually-billed external send the moment its
buckets let a request through (`PhoneVerificationDeliveryConsumer`, `Ago.Chat.Worker`). Every request
that clears all three existing buckets costs real money, not shared capacity.

**The per-site bucket does not close this, and the reason is precise, not approximate.** `PerSiteCapacity`
(100/hour, `PhoneVerificationRateLimitOptions`'s own default) does bound the *total* cost one tenant's
site can be made to absorb per hour — a real ceiling, already in place. What it does not do is separate
*whose* consumption counts against that ceiling: the bucket is shared across every visitor to that site,
by design (the identical "one shared budget per site" shape `CreateAttachmentHandler`'s own site bucket
already uses). A single hostile caller who mints enough distinct visitor sessions — cheap: `AuthEndpoints`'
own `/api/v1/visitor-sessions` is rate-limited **per-site only** (`VisitorSessionRateLimitOptions`), not
per-IP either, so nothing today stops one machine from minting as many visitors as the site's own
session-minting budget allows — can exhaust the *entire* site-wide phone-verification budget alone. The
cost this produces is bounded (100 real sends/hour, indefinitely, hour after hour, until someone
notices); the **denial of service** it produces is not bounded at all: every legitimate customer of that
shop is locked out of verifying a phone for as long as the attacker keeps the shared bucket empty. A
competitor with no interest in the SMS cost itself, only in making a rival's booking flow appear broken,
gets that for the price of one unauthenticated script.

**Nothing in this call chain is keyed on the caller's network origin today.** Confirmed by reading the
real code, not assumed: `InitiatePhoneVerificationAsVisitor` (the command) carries `ConversationId`,
`RequestedBy`, `Phone` — no IP. `PhoneVerificationEndpoints.cs` never reads
`httpContext.Connection.RemoteIpAddress`. This is not an oversight unique to `14-15` — it is the one
endpoint in this call chain where the omission has a real cost attached, unlike ordinary conversation
traffic.

## Decision

**Add a fourth bucket, per-IP, checked first** — before phone, before visitor, before site — the
identical "cheapest, coarsest check rejects a bad caller before any database work" ordering
`RegisterSiteHandler` already establishes for its own subject/IP pair. Concretely:

- `InitiatePhoneVerificationAsVisitor` gains a `RequestIp` field, threaded from
  `PhoneVerificationEndpoints.cs` the same way `RegisterSiteHandler`'s own `RegisterSite.RequestIp` is —
  `httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"`. No forwarded-header parsing:
  `edge.md`'s own architecture note (the Gateway terminates client connections directly, no proxy hop
  this project does not control) is why `RegisterSiteHandler` trusts `RemoteIpAddress` directly today,
  and the identical deployment topology makes it equally trustworthy here.
- `PhoneVerificationRateLimitOptions` gains `PerIpCapacity`/`PerIpRefillPerSecond`, checked in
  `InitiatePhoneVerificationHandler` before the existing per-phone bucket — reordering the existing
  three, not just appending a fourth, so a single-machine attacker is rejected by the coarsest, cheapest
  check before ever touching the phone-specific bucket a legitimate high-volume shop's own visitors
  might legitimately be sharing.
- **The visitor-session minting endpoint gets the identical treatment, named here rather than left as a
  second, unfixed instance of the same gap**: `VisitorSessionRateLimitOptions` gains a per-IP bucket
  too. Without it, this ADR's own fix is a half-measure — an attacker who cannot iterate visitors fast
  enough per IP to matter downstream simply mints fewer, more, from more IPs upstream, and the real
  bottleneck this decision closes (one IP, many visitors, one exhausted site budget) reopens one layer
  earlier.

**Not proposed**: an IP-based *block list*, CAPTCHA, or any mechanism beyond a token-bucket rate limit.
This is scoped narrowly to the shape every other bucket in this codebase already uses — `IRateLimiter`'s
existing contract, no new abstraction, no new infrastructure dependency.

## Consequences

- **Positive**: a single-IP attacker attempting the "exhaust the shared site budget via many minted
  visitors" path is now capped at their own bucket, independent of how many distinct `VisitorId`s they
  mint — the site's own shared budget stays available to everyone the attacker is not personally
  occupying.
- **Positive**: no new infrastructure. `IRateLimiter`/`RateLimitRule`/`RateLimitKey` already exist and
  are already used this way, four times over, in this codebase (`RegisterSiteHandler`,
  `CreateAttachmentHandler`, `14-15`'s own three buckets, `20-03`'s Calendar-side phone bucket).
- **Negative, named plainly**: an IP-based bucket is a weaker signal behind CGNAT or a shared corporate
  network — a genuine burst of unrelated legitimate visitors from one large NAT'd network could
  collectively trip a per-IP bucket sized for one attacker. `RegisterSiteHandler`'s own default
  (`PerIpCapacity = 10`/hour) is far more conservative than what phone verification's own legitimate
  traffic pattern likely needs (a real shop's own visitors verifying phones one at a time, rarely from
  one shared IP in volume) — the actual default for this bucket is a judgment call for whoever
  implements this, stated as an open question below rather than guessed at here.
- **Negative**: does not close the threat entirely. A distributed attacker (many real IPs, not one
  machine) is unaffected by any per-IP bucket — the per-site bucket remains the real, final backstop
  against that case, exactly as it is today. This decision narrows the easy, cheap version of the attack
  (one script, one IP); it does not claim to solve the hard, resourced version of it.
- **Negative**: IP address is personal data (`personal-data.md`'s own scope). This decision holds it
  only as an ephemeral rate-limit key in Redis, the identical pseudonymised, short-TTL shape the
  existing phone/visitor/site buckets already use for their own keys — never persisted, never logged
  alongside an identity, never a new durable record. No change to this codebase's own personal-data
  posture, only a fourth use of a pattern already accepted three times over.

## Alternatives considered

- **Rely on the per-site bucket alone, unchanged.** Rejected: bounds cost, does not bound denial of
  service to a shop's own legitimate customers — the sharper, more concrete harm the account owner's
  own framing ("конкуренты будут тыкать") actually describes. A competitor rarely cares about $2 of SMS
  cost; they care about a rival's booking flow looking broken to real customers.
- **A CAPTCHA or similar bot-challenge on `InitiatePhoneVerificationHandler`.** Rejected for this item:
  a real UX cost on every legitimate visitor, for a threat a rate-limit bucket already closes at the
  cheap end. Worth reconsidering only if a per-IP bucket proves insufficient against a real, observed
  attack — not assumed necessary up front.
- **Block or challenge the visitor-session-minting endpoint only, leave phone verification's own three
  buckets unchanged.** Rejected as incomplete on its own: closes the upstream supply of cheap visitors,
  but a determined caller can still iterate slowly enough to stay under the site's own session-minting
  budget while still exhausting the *phone-verification* site bucket specifically, since that bucket has
  no IP awareness of its own today. Both endpoints need the fix; neither substitutes for the other.

## Open questions

- The actual `PerIpCapacity`/`PerIpRefillPerSecond` defaults for this specific bucket — not measured,
  and deliberately not guessed at in this ADR (`CLAUDE.md`'s own "do not invent numbers" rule).
  `RegisterSiteHandler`'s own default (10/hour) is a starting point to weigh against, not a value to
  copy blindly — phone verification's own legitimate traffic shape has not been measured either.
- Whether the visitor-session-minting endpoint's own per-IP bucket (named as in-scope above) ships in
  the same change as this one, or as an immediate, separate follow-up — an implementation-sequencing
  call, not a design one; either is faithful to this decision as long as neither is silently dropped.
