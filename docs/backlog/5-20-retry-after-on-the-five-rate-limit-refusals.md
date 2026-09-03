# Give the five rate-limit refusals a `Retry-After`

- **Stage**: 5
- **Status**: ready
- **Found**: 2026-09-03, while fixing `5-18`/#347 — `ErrorExtensions`' own comment already named it.

## The gap

Five codes map to **429** correctly — `Message.RateLimited`, `Site.RateLimited`, `Export.RateLimited`,
`ReplyDraft.RateLimited`, `PhoneVerification.RateLimited` — and not one of them sets `Retry-After`.

A 429 without it tells a caller to back off and refuses to say for how long. The honest options left
are to retry blindly or to guess, and both are worse than being told.

## Why `#347` did not simply extend to these

That fix needed the header for one endpoint and got it by reading the number back out of the error's
own message, producer and parser colocated with a round-trip test binding them. It works for one code
and does not generalise: **`Ago.Platform.Kernel.Error` is `(Code, Message)` only**, with nowhere to put
a structured retry-after. Every one of these would need the same trick, or the type has to change.

Widening `Error` is a **platform** change, so `CLAUDE.md`'s qualifying rules apply — premature
generalisation is the failure mode of a platform layer, and "five call sites in one product want it"
is exactly the argument that needs testing rather than assuming.

## The trap, recorded before anyone starts

**Do not recover the number by asking the rate limiter again at the HTTP layer.** `RedisRateLimiter`'s
Lua script decrements the bucket only on an *allowed* check, so a second check per request would
consume a token and **silently halve every configured limit** — a correctness bug worse than the
missing header, and one whose symptom is a lower limit rather than an error. `#347` considered this
and rejected it.

## The decision this needs

The choice is the work, not the typing:

1. **Widen `Error`** to carry structured detail — solves it once, changes the platform, needs the
   qualifying argument made rather than assumed.
2. **Per-endpoint handling outside `Result<T>`**, as `AuthEndpoints.HandleVisitorSessionAsync` already
   does — no platform change, five near-copies.
3. **The `#347` shape** — parse the number back out of the message. Cheapest, and the least honest of
   the three about what `Error` actually models.

## Done when

- [ ] The chosen shape is stated with what it replaced and why the alternatives were rejected.
- [ ] Each of the five 429s carries a `Retry-After` a client can parse, asserted by a test.
- [ ] No path checks a rate limiter twice per request — proven, not assumed, since the symptom is a
      halved limit rather than a failure.

## Out of scope

- The four unmapped `demo.*` codes. Separate promise, and done: `5-19`.
