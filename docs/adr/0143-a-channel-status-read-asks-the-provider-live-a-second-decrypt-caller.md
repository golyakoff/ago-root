# ADR-0143: a channel status read asks the provider live - the second real caller of `Decrypt` outside an outbound send

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-36`)

## Context

`23-36` gives a tenant a console screen to connect their own Telegram bot, replacing the "somebody with
a terminal" gap `23-31` found while drawing the navigation. The item's own brief is explicit about what
"connected" has to mean: *"'Connected' must mean the provider agreed, not that a string was saved. A
screen that accepts a typo and reports success produces a tenant who believes they have a channel and
has silence."* `TelegramChannelEndpoints.HandleConnectAsync` already honours that at entry - it calls
Telegram's own `getMe` once, live, before ever returning success.

What it does not cover is the moment after entry. `ChannelCredential.Active` is a stored bit, set once
at registration and never re-checked against the provider; a bot deleted or a token reset at Telegram's
own side leaves that bit `true` indefinitely. `adr/0069` already named this as a real, accepted gap -
*"Revocation has no tenant-facing notification mechanism yet... nothing pushes an alert to the shop
that their channel stopped working"* - and `23-36`'s own brief restates it as the one Scope item the
backend genuinely did not have: *"What the tenant sees for a channel that stopped working... today
nothing surfaces it."*

A console screen that shows a green tick sourced from `Active` alone would be exactly the failure mode
the brief opens with, just moved one step later: a stored flag standing in for the provider's own
answer. The fix is mechanical once stated - ask Telegram again, live, whenever the tenant looks - but
`adr/0069` contains a sentence that this decision now makes false: *"No use case this item ships calls
`IChannelCredentialCipher.Decrypt` from a read path; the only caller is the outbound send."* That claim
was already narrower than the code even before this item - `TelegramLongPollingService` and
`MaxLongPollingService` both decrypt to poll `getUpdates`, which is inbound, not an outbound send - but
nothing before now made an operator-facing *read* endpoint decrypt a token. This ADR is that decision,
recorded rather than made silently, because CLAUDE.md's teaching-mode rule treats "which layer calls
`Decrypt`" as exactly the kind of placement that needs its reasoning stated, and because a prior ADR's
own sentence is what this item now contradicts.

## Decision

`GET /api/v1/sites/{siteId}/channels/telegram` (`TelegramChannelEndpoints.HandleStatusAsync`) decrypts
the site's active Telegram credential and calls `TelegramApiClient.GetMeAsync` on every read - not once
at registration, every time the console screen loads or is refreshed. The response carries `Connected`
(is there an active credential), `Verified`/`RefusalReason` (what Telegram just said about it) and
`CheckedAt` - never the token, and never anything derived from it beyond a boolean and Telegram's own
refusal text.

**The read stays split the same way the write already is.** `GetChannelCredentialStatusHandler`
(Application, channel-neutral) is the only thing that checks `Permission.ChannelManage` and reads
`ChannelCredentialId`/`CreatedAt` from the repository - the identical shape
`RegisterChannelCredentialHandler`/`RevokeChannelCredentialHandler` already have, and the reason a
caller who lacks the permission, or holds it for a different site, learns nothing (`GetActiveAsync` is
scoped by `SiteId` at the query itself, never filtered afterward). The live provider call is
Telegram-shaped work, so it stays in the host (`Ago.Chat.Api`), exactly where `HandleConnectAsync`'s own
`getMe` call already lives - `adr/0006`'s "largest common denominator" reasoning, restated for the read
side rather than re-argued.

**A failed live check does not revoke the credential by itself.** Only an explicit `DELETE` (the
tenant's own Disconnect action) calls `RevokeChannelCredentialHandler`. A status read that silently
flipped `Active` to `false` on a bad `getMe` answer would make a routine page load a state-changing
write, and would treat a passing outage identically to a real revocation - `TelegramApiClient.GetMeAsync`'s
own remarks already draw exactly this distinction for the connect-time case ("a transient fault...
deliberately not rolled back... revoking a possibly-good credential because of an outage the operator
did nothing to cause would be the wrong failure mode"), and it applies with the same force here, once
more per read instead of once at registration.

**The live call is bounded to 5 seconds - found missing, not part of the original design.** `ChatModule`
registers `TelegramApiClient`'s own `HttpClient` with a base address, a SOCKS5 proxy handler
(`TelegramProxyOptions` - this deployment reaches Telegram through a relay, which is itself a second
thing that can be down) and the token-redacting log/trace handlers, and sets no `Timeout` - so it
inherits `HttpClient`'s own 100-second default. That is tolerable for the connect-time call this read
was modelled on (a deliberate action an operator just took once); it is not tolerable for a read that
runs on every load of the console's Telegram screen, where an unreachable provider or a dead proxy would
otherwise hang the screen for up to a minute and a half before rendering anything - exactly backwards
for a screen whose whole point is telling the tenant the truth quickly. `TelegramLiveTokenCheck` (in
`Ago.Chat.Infrastructure.Telegram`, alongside `TelegramApiClient`) wraps the call with a linked
`CancellationTokenSource` at a 5-second bound, matched to `ChatModule.ConfigureChannelResilienceDefaults`'s
own `Timeout` value - the closest existing boundary of the same shape (a third-party HTTP call with a
real person waiting on the other end) - rather than inventing a number. It deliberately does **not**
reuse that pipeline's retry/circuit-breaker: those are wired around the *send* path
(`ResilientInboundChannelAdapter`), and retrying a status read the same way would make an unreachable
provider's page load slower, not more useful, for a read a tenant is actively watching.

**The bound produces a third outcome, structurally distinct from a refusal.** `TelegramLiveTokenCheck.RunAsync`
returns one of exactly three shapes: verified, refused (Telegram looked at the token and said no,
`RefusalReason` set), or unreachable (the call did not complete - a timeout, or the identical transient
`HttpRequestException` `TelegramApiClient.GetMeAsync`'s own remarks already describe for the connect-time
case - `RefusalReason` always `null`). Collapsing "could not reach Telegram" into the same `Verified:
false` a refusal produces would tell a tenant whose bot is fine, but caught behind a momentary proxy
hiccup, to go generate a new token for no reason - two different facts a tenant acts on differently (wait
and retry, versus get a new token), which is exactly why `TelegramChannelStatusResponse` carries a
separate `Unreachable` flag rather than folding it into `Verified`/`RefusalReason`. Found during review,
not in the original design - the first version of this endpoint called `GetMeAsync` directly, unbounded,
and let a failure to reach Telegram surface as a refusal or an unhandled exception depending on which
kind of failure it was.

## Consequences

**Positive.** The console never has to choose between "the database says active" and "the provider
actually agrees" - it only ever shows the second, which is what `23-36`'s own brief demands. The
mechanism is the connect flow's own `getMe` call, reused rather than duplicated with different
semantics.

**Negative, stated rather than glossed.**

- **`adr/0069`'s "the only caller is the outbound send" is now stated wrong twice over** - once
  already, by the long-polling services' own inbound decrypts, and now explicitly by this read path.
  This ADR is the correction; `adr/0069` itself is not edited, the way an ADR is never rewritten to
  agree with a later one (`docs/adr/README.md`'s own convention - superseding, not editing).
- **A live call on every status read is an extra outbound request per page view**, not free, and not
  cached - deliberately, since caching "is this still connected" is exactly the kind of write-adjacent
  read CLAUDE.md rule 8 warns against treating loosely, even though this one is not a compare-and-set.
  No rate-limit concern is known for Telegram's own `getMe`, and none is invented here either
  (CLAUDE.md: "do not invent numbers... measure or stay silent") - if this becomes a real cost, the fix
  is a short server-side cache with its own TTL, not reverting to the stored flag.
- **A revoked-but-still-shown-as-connected credential remains possible between an operator's disconnect
  click and their next status read**, exactly as it already was for every other race in this system -
  nothing about this ADR closes that window, it only makes the *ordinary* case (a token that quietly
  stopped working, nobody having touched the console) honest instead of silent.
- **This still does not solve `adr/0069`'s named gap of an unprompted alert.** A tenant who never
  reopens the channel screen still is not told their bot died - this ADR makes the fact available the
  moment they look, not sooner. Closing that gap for real is a notification mechanism, out of `23-36`'s
  own scope and not attempted here.

## Alternatives considered

- **Trust `ChannelCredential.Active` alone, no live call.** Rejected outright - this is the exact
  failure `23-36`'s own brief opens with, restated at read time instead of write time.
- **Have the background poller (`TelegramLongPollingService`) persist a health signal the status read
  can trust instead of calling Telegram itself.** Rejected for this item: that poller already decrypts
  and calls Telegram continuously, so it is the cheaper source of truth in principle, but it currently
  treats every failure identically (a generic `catch (Exception ex)`, logged and retried) with no
  distinction between "Telegram is down" and "this token was revoked", and it persists nothing back to
  `ChannelCredential` at all. Building that distinction and a new persisted column is real, separate
  work - `adr/0069`'s own gap, not this item's to close - and doing it well is worth its own item rather
  than a rushed half-measure bolted onto a console screen's own scope.
- **Auto-revoke on a failed live check.** Rejected - see Decision above: conflates an outage with a
  real revocation, and turns an idempotent `GET` into a write, which `RevokeChannelCredentialHandler`'s
  own idempotent-disconnect shape already exists to be the one place that happens deliberately.
- **Cache the live result for some window rather than calling Telegram on every read.** Not rejected so
  much as deferred - no measured cost yet justifies the added complexity of a TTL and its own staleness
  question, and CLAUDE.md rule 7 requires a number this item does not have. Named in Consequences as the
  correct fix if the plain per-read call ever turns out to be too much.
- **Wrap the status read in `ChatModule`'s existing `Channels` resilience pipeline (retry + circuit
  breaker), instead of a bare timeout.** Rejected: that pipeline's own three retry attempts with
  exponential backoff exist for the *send* path, where a human is waiting on the other end of an
  operator's reply, not a page load. Applying the identical retry budget here would mean a tenant
  watching an unreachable provider waits for up to three attempts' worth of backoff before the screen
  ever says so - slower, not more honest. A bare timeout, matched to the same pipeline's own `Timeout`
  value, gets the one property this read actually needs (a bound) without the property it does not
  (persistence through transient failure).
- **Leave the call unbounded and let a timeout surface as an unhandled exception, the same as the
  connect-time call.** This was the first version of this item, corrected during review: a status read
  runs on every page load, unlike a one-off connect action, so an unhandled 100-second hang is a
  materially worse failure mode here, and an unhandled exception gives the console a 500 to render
  rather than the honest "could not reach Telegram just now" the brief asks for.
