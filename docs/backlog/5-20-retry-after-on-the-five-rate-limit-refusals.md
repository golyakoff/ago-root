# Give the five rate-limit refusals a `Retry-After`

- **Stage**: 5
- **Status**: done (2026-09-03), `ago-chat#158`
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

- [x] The chosen shape is stated with what it replaced and why the alternatives were rejected. —
      each endpoint derives the wait from the `*RateLimitOptions` its own handler already used.
      Widening `Error` was rejected as a platform change five call sites in one product do not
      justify; `#347`'s read-it-back-out-of-the-message shape was rejected as five near-identical
      parsers of prose.
- [x] Each of the five 429s carries a `Retry-After` a client can parse, asserted by a test. —
      delta-seconds, ceiling, clamped to at least 1 because `ago-widget` treats a `0` as "retry now".
- [x] No path checks a rate limiter twice per request — proven, not assumed, since the symptom is a
      halved limit rather than a failure. — **and the tests could not have proven it**: a fake
      limiter does not decrement, so a test passes just as happily against an endpoint that checks
      twice. What proves it is structural — all sixteen `rateLimiter.CheckAsync(` call sites are
      still on the same sixteen lines in the same eight files, and the five handlers that own the
      real check have a zero-line diff.

## Out of scope

- The four unmapped `demo.*` codes. Separate promise, and done: `5-19`.

## Outcome

Done 2026-09-03, `ago-chat#158`.

**The slowest bucket, not the one that actually denied the call.** `Error` carries no marker for which
tier refused — by design, since that is precisely the structured detail it does not model — so the
slowest-refilling bucket's own worst case is the only answer that is never too short. Slightly
pessimistic, never premature.

**`PhoneVerification.LockedOut` keeps carrying no header**, deliberately: no wait fixes it, only a new
pending verification. Confirmed untouched rather than overlooked — it is a different handler from the
one this change edits.

**One edge flagged rather than fixed.** `Conservative` computes `1 / refillRatePerSecond` and none of
the `*RateLimitOptions` carry a `[Range]`, so a configured `0` would give infinity and turn a 429 into
a 500. A zero refill rate is an already-broken configuration — the limiter would deny permanently
after the first burst — but this path previously returned 429 under *any* configuration and now might
not. Left alone deliberately rather than changed after the suite had run.

**A number that reconciled rather than surprising.** The branch was cut before `22-05` and rebuilt on
the `main` that contains it: 761 integration tests is `22-05`'s 747 plus this item's 14, checked
rather than accepted, because the counts either side of the rebase would otherwise look inconsistent.
