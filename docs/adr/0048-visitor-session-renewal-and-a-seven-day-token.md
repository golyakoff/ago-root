# ADR-0048: visitor sessions renew at the point of use, and the token drops to seven days

- **Status**: Accepted
- **Date**: 2026-08-25
- **Stage**: 17

## Context

`adr/0034` set the visitor token's lifetime at 30 days and, unusually for a lifetime decision, spent
most of its reasoning on why the number could not move. The obstacle was not security analysis, it
was a client: `ago-widget` stored the first token it was ever given and reused it forever. It never
inspected `exp` and never re-minted. So the lifetime was not a security parameter at all — it *was*
"how long a returning visitor still sees their own conversation", and lowering it to 7 days would
have moved the day the widget silently stops working from day 31 to day 8 while buying nothing.

Nothing buys anything, in fact, until two facts stop being the same number. `17-07` is where they
separate, and this ADR records how.

Three constraints from `adr/0034` are inputs here rather than open questions:

- **The minting endpoint is public and unauthenticated by design** (`POST /api/v1/visitor-sessions`,
  `api-design.md`) — a site's public key is not a secret. Anyone positioned to read a visitor token
  can mint their own for the same site. A shorter lifetime is therefore **not** an anti-theft
  measure; what it bounds is one visitor's own transcript staying reachable from a shared or lost
  device, and how long a single token stays valid after the key that signed it should have gone
  (`17-03`).
- **There is no revocation and deliberately none planned.** No deny-list, because nothing in the
  system can currently decide that one token should stop working.
- **The current failure mode is silence.** An expired token prompts nothing; the widget keeps
  presenting it and the connection simply fails.

## Decision

### The lifetime is 7 days, and it is sliding with no absolute cap

`JwtTokenService.VisitorTokenLifetime` becomes `TimeSpan.FromDays(7)`. Each renewal issues a full
fresh 7 days, so a visitor who keeps coming back never expires; a visitor who stays away for a week
does.

`17-07` owed an answer on **sliding versus an absolute cap** after which re-identification is forced
regardless of activity. The answer is **sliding, with no cap**, and the reason is that a cap here
does not do what a cap normally does.

A cap is usually "an attacker who stole a session is eventually evicted". That is not available in
this system, from either side. The attacker is not evicted, because the minting endpoint is public —
at any moment before or after the cap they can mint a working token for the same site; the only thing
they lose is the binding to *that visitor's* transcript. And the visitor cannot re-identify, because
there is no visitor login: nothing about a returning browser can prove it is the same person. So an
absolute cap reduces to a scheduled date on which every long-running visitor loses their history in
exchange for narrowing one attacker's window from "as long as the visitor keeps using the site" to
"the cap". Given that the same attacker keeps a working token either way, that trade is not worth a
guaranteed product harm.

**The trigger that changes this answer**, stated so a later session checks rather than re-derives:
the first time a visitor can identify themselves — an email, a verification code, `16-02`'s erasure
surface, anything that lets a person reclaim a conversation without holding the original token. A cap
costs nothing the moment re-identification exists, and it should be added then.

`17-03`'s key-rotation drain window inherits this number: **7 days**. A retired visitor signing key
must stay in the validation set for 7 days after rotation, because that is the longest a token signed
by it can still be presented by an honest visitor.

### Renewal happens at the point of use, not on a timer

There is no `setInterval` in the widget. The token is presented in exactly three places — the hub's
negotiate, and the attachment REST calls — and each goes through one method that renews first if the
token is inside its renewal window.

The alternative, a timer that fires when renewal is due, was rejected on three counts. It fires in
background tabs, on a page the widget does not own, for a visitor who may never interact. It does not
fire at all across a device sleeping through the moment it was scheduled for, which is the common
case for a multi-day window — so the timer design needs a wake-up check anyway, which is the at-use
design with extra machinery. And it renews tokens that were never going to be used.

The case that makes at-use renewal not merely equivalent but correct: **`@microsoft/signalr` calls
its `accessTokenFactory` on every negotiate, including every automatic-reconnect attempt.** A
connection established days ago and dropped is re-established with whatever that factory returns
*now*. Putting renewal behind the factory means the reconnect after a long idle carries a token that
is valid at the moment it is presented, which is the single behaviour that decides whether a
long-lived widget survives its own token's lifetime.

This also closed a live defect that `5-17` had flagged as latent: `ago-widget`'s factory closed over
a captured token, "harmless only because the token never rotates". It rotates now, so a captured
token would have meant a reconnect negotiating with a value renewal had already replaced — the
visitor left on "Reconnecting…" forever, which is precisely the silence this item exists to remove.
`ago-console` reached the same shape in `5-16`, from the other token issuer.

**The renewal window is one third of the token's own lifetime**, read from the token (`exp - nbf`)
rather than from a constant mirroring the server's. The widget does not know the server's lifetime
and should not: the same code is correct against the 30 days deployed before this and the 7 days
after, and a client-side copy of that number would be a second place to change and a silent breakage
when only one moved. A third of 7 days opens the window with 2.3 days left, so any visitor who loads
the page even once in that window renews.

### The expiry check reads `exp` from the token rather than storing it alongside

`17-07` asked for this to be decided either way. `storage.ts`'s `VisitorSession` already carries
fields beyond the token, so a stored `expiresAt` was a real option.

Rejected, decisively, on the migration case: a returning visitor holding a token minted before this
shipped has no stored expiry and never will, so a stored-expiry design must read "no expiry recorded"
as either "renew immediately" — a renewal storm on release day, against a rate-limited endpoint — or
"assume valid", which is exactly the pre-`17-07` silence. Reading `exp` works on the tokens that
already exist, which is the entire population on the day it ships. Secondarily, a stored copy of a
fact the token itself carries can drift from it; the token is what the server will judge.

**This is explicitly not an authorization decision.** The widget verifies no signature and trusts no
claim; it decodes a payload to decide *when to ask for a new token*. The server re-validates on every
presentation, so a token lying about `exp` costs at most one extra rate-limited request (too early)
or a failed connect that already has a handled path (too late).

### Re-identification only ever happens at a page load

Renewal makes expiry rarer; it does not remove it. Two moments remain, and they get **different**
answers, which is the part worth recording.

**A stored token the server will not renew, at page load** — the visitor was away longer than the
window, or `17-03` rotated the key out. The widget **mints a new identity, clears the stored
conversation cursor, and says so in the panel**: one system note stating the previous conversation
has expired and is not shown here. Minting is not optional — this bundle runs on a stranger's page
and must not present a dead widget — but silence is, and `adr/0034` named silence as the thing this
item should make observable rather than move. Clearing the cursor is not cosmetic: a
`lastKnownSequence` from a conversation the new `VisitorId` does not own would make the first
resuming `JoinAsync` ask for a delta above a sequence in someone else's transcript, and the visitor
would watch their own new messages fail to appear.

**A token the server refuses to renew while the page is open** — the widget **does not
re-identify**. It ends the session visibly: the composer is disabled, the connection is stopped, and
the panel says the session has expired and a reload starts a new one. Minting here would open a
different conversation *underneath a transcript belonging to the first one*, and the visitor would
carry on typing to an operator who cannot see any of it, with nothing on screen looking wrong. The
connection is stopped rather than left retrying because SignalR's reconnect loop would otherwise ask
for a token forever, and each attempt now costs a renewal request against a server that has already
refused.

A transient failure is not either of these. An unreachable API, a `5xx`, or a `429` leaves the
visitor on the token they still hold and is retried later, throttled to at most one attempt a minute
so a dead API costs one request per minute rather than one per reconnect attempt. Only a definitive
`401`/`403` ends an identity. Conflating the two would turn a thirty-second outage into every
in-flight visitor losing their conversation.

### The endpoint: `POST /api/v1/visitor-sessions/renew`

A separate endpoint rather than a flag on the minting one, because the two differ in the only thing
that matters: renewal preserves the `VisitorId`, and re-minting through the public endpoint already
"works" and is exactly what loses the history.

- **Authenticated on the Visitor scheme.** The caller proves the identity being renewed by presenting
  the token being renewed; `sub` and `site_id` come from the validated principal, never from the
  body.
- **Body carries the site's public key**, as the mint does, and the handler rejects a request whose
  resolved `SiteId` does not match the token's claim. This reuses the existing cached
  `GetSiteConfigByPublicKeyHandler` lookup rather than adding a query by `SiteId`, and it gives the
  rate limiter the same key shape `3-05` already uses.
- **`200 OK`, not `201`** — nothing is created; one identity continues.
- **The same response shape as the mint.** Deliberate, and it closes a limitation
  `ago-widget/src/storage.ts` had written down as unfixable: it said fixing stale cached widget
  config "needs a session endpoint that can return current config without minting a new visitor", and
  this is that endpoint. A returning visitor's cached colour/position is now at most one renewal
  window stale instead of frozen at the moment their identity was first minted.
- **Rate-limited per visitor**, `visitor-session-renew:visitor:{visitorId}`, rather than per site as
  the mint is. The mint has no choice — there is no visitor identity yet, which is the whole point of
  the call. Renewal does, and per-visitor is strictly better there: one abusive holder of a valid
  token cannot exhaust a bucket shared with every honest visitor on the same site. `429` carries
  `Retry-After`, which the widget honours with jittered backoff exactly as it does for the mint.
- **Origin checked** against the site's `AllowedOrigins`, the same second layer the mint applies
  (`5-01`).

## Consequences

- **The lifetime and the product promise are no longer the same number.** "How long a returning
  visitor keeps their history" is now unbounded for an active visitor; "how long one token stays
  useful" is 7 days. Every later argument about either can move one without the other.
- **`17-03`'s drain window is 7 days**, and is now derived rather than inherited by accident.
- **A visitor away for more than a week loses their transcript, visibly.** This is a real product
  regression against 30 days, taken knowingly: the note in the panel is what makes it a stated
  behaviour rather than an empty widget, and the cap discussion above is why the alternative is not
  better.
- **The widget carries a JWT payload decoder** (`tokenExpiry.ts`, ~40 lines) it did not before. It is
  the one piece of this change that could be read as the client making a security judgement, and its
  own header exists to say it is not. The bundle went from 21.0 KB gzipped to **22.0 KB**, against a
  45 KB budget.
- **The renewal endpoint is a credential-issuing endpoint that did not exist**, and it is authenticated
  where the mint is not. That is a smaller attack surface than the mint, not a larger one — the
  caller must already hold a valid token — but it is one more place that writes a token, and it is
  rate-limited for that reason rather than because abuse is expected.
- **`adr/0034`'s visitor-token section is superseded in part**, not wholesale: its reasoning about
  *why* 30 days could not simply be lowered remains correct and is the reason this ADR exists. Only
  the number and the "no renewal path" premise change.
- **`ago-widget` no longer works against an `Ago.Chat.Api` that lacks the renewal endpoint** in one
  narrow case: a visitor whose token is inside the renewal window gets a `404`, which is a transient
  failure by this design, so they carry on with their existing valid token and the renewal is retried
  and fails harmlessly until the token expires. That is deliberately the same behaviour as an
  unreachable API — the widget degrades to exactly the pre-`17-07` behaviour rather than breaking.

## Alternatives considered

- **A renewal timer.** Rejected above: it fires in background tabs on a page the widget does not
  own, and does not fire at all across a sleeping device — so it needs a wake-up check anyway, which
  is the at-use design plus machinery.
- **Storing the expiry beside the token instead of reading `exp`.** Rejected on the migration case:
  every already-stored session has no expiry field, forcing a choice between a renewal storm and the
  silence this item exists to end.
- **An absolute cap on top of sliding renewal.** Rejected above. It evicts the honest visitor and not
  the attacker, because the minting endpoint is public and there is no way for a visitor to
  re-identify. Named trigger recorded instead.
- **Silently re-minting when a token expires mid-session.** Rejected: it moves the visitor to a new
  conversation while the previous one is on screen, so they type to an operator who cannot see it and
  nothing looks wrong. This is worse than the silence it would replace.
- **Surfacing an error and stopping at page load too**, instead of minting a new identity. Rejected:
  a visitor arriving at a shop and finding a chat widget that refuses to open is a broken site as far
  as they can tell, and the widget's first rule is that it never becomes that.
- **A flag on `POST /api/v1/visitor-sessions` (`renew: true`) instead of a second endpoint.**
  Rejected: it would make one endpoint both public-unauthenticated and authenticated depending on a
  body field, with different rate-limit keys and different status codes on the two paths. Two
  endpoints is the smaller thing to reason about, and `api-design.md`'s versioning rule cares about
  response shapes, not endpoint counts.
- **Refresh tokens, or an opaque server-side session.** Both answer revocation properly and both are
  a different system. `adr/0034` already rejected the opaque-session direction as replacing the
  widget's whole identity model, and a refresh token adds a second credential to store in the same
  `localStorage` as the first, which buys nothing when the mint endpoint is public.
