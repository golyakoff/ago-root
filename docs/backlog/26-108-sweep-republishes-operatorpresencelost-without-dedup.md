# 26-108 · The disconnect sweep re-publishes `OperatorPresenceLost` every tick without dedup, amplifying the grace queue

- **Stage**: 26
- **Status**: ready — engineering defect with a self-contained fix; the grace-period timing and the
  mobile-backgrounding UX questions stay with `26-84`, this item does not touch them.
- **Found**: 2026-09-25, code-inspection half of `26-84`/`26-83`'s "distinguish the two candidate
  causes" investigation. Filed by the managing session, not worked around silently.

## What is actually true today, confirmed against the real code

`OperatorDisconnectSweepJob.SweepAsync` (`ago-chat`, `Ago.Chat.Worker`) runs every
`Interval` (**default 15s**) and, for **every** operator that has at least one `Assigned` conversation
and zero live connections in `IConnectionRegistry`, calls `presencePublisher.PublishLostAsync(...)`.
There is **no per-operator dedup and no "a `OperatorPresenceLost` for this operator is already
in-flight / being graced" guard.**

`OperatorDisconnectGraceConsumer` waits `GracePeriod` (**default 30s**) holding the delivery unacked,
then re-checks presence once and releases. So from the instant an operator loses all connections until
the grace consumer actually moves their conversations out of `Assigned` (≥30s later, longer if the
consumer is backed up), the operator still matches the sweep's query — and **each 15s sweep publishes
another `OperatorPresenceLost` for the same operator.** At minimum ~2 duplicates per genuine
disconnect; unboundedly many if release is delayed.

The grace consumer is correctness-idempotent (its own doc comment: a redelivered/duplicate Lost "just
waits and re-checks again, harmless" — `ReleaseAllAsync` skips already-released conversations). So the
duplicates do **not** cause wrong releases. What they cause is a **queue-throughput problem**: every
duplicate holds a delivery unacked for the full 30s `GracePeriod`, and the consumer's prefetch ceiling
is 50, so drain rate is ≈50 / 30s. When duplicate publishes arrive faster than that, the
`operator-disconnect-grace` queue pins at 50 unacked with a growing `messages_ready` backlog.

This is exactly `26-84`'s observed live symptom (08:40–09:04 UTC, demo stand): `messages_unacknowledged`
pinned at a constant **50** for 20+ minutes, `messages_ready` climbing 4→14 and draining slowly well
past the end of active testing.

## Why this is separable from `26-84` and `26-83`

- `26-84` is the product/UX item: *should* backgrounding a phone release conversations, and with what
  grace timing. That needs the author's decision and a real-device proof. This item changes neither the
  grace period nor the release behaviour — a genuinely-gone operator is still released exactly once.
- `26-83` is "push **sends** arrive in periodic bursts" — a separate observation about notification
  delivery cadence. It may or may not share this root cause; this item does not assume it does.
- The fix here lands green on its own: the backstop stays a backstop (still catches a disconnect that
  never fired the fast-path `OperatorPresenceLost`), it just stops re-firing while a Lost for that
  operator is already being handled. No other list, consumer, or product behaviour changes.

## Scope

- Make `OperatorDisconnectSweepJob` idempotent per disconnect: before publishing `OperatorPresenceLost`
  for an operator, skip if one was recently published for that same operator (a short-lived suppression
  marker keyed by `operatorId`, TTL ≈ `GracePeriod` + a small margin so the marker outlives the window
  in which the operator still matches the query). Redis is already a dependency here
  (`IConnectionRegistry`); an in-proc marker is not sufficient because the sweep is `Competing`-style
  across Worker replicas and two replicas could each publish — prefer a shared marker (a Redis SET NX
  with TTL, or equivalent) so dedup holds across replicas.
- The fast-path publish in `OperatorHub.OnDisconnectedAsync` and the sweep should share the same
  suppression key, so the sweep does not immediately duplicate a fast-path Lost the API just sent.
- Keep the existing behaviour for a truly missed disconnect: if no Lost was recently published (marker
  absent/expired), the sweep still publishes — that is the whole point of the backstop.
- A unit/integration test proving: two consecutive sweep ticks for the same still-gone, still-`Assigned`
  operator publish `OperatorPresenceLost` exactly **once**, and a second genuine disconnect after the
  marker TTL publishes again.

## Out of scope

- The `GracePeriod` / `Interval` values themselves (`26-84`'s question).
- Any client-side change (the Android client does not storm on ordinary backgrounding — confirmed:
  `disconnect()` gates the reconnect loop, and `26-85`'s foreground service keeps the socket alive).
- The prefetch ceiling / consumer-throughput redesign (`OperatorDisconnectGraceConsumer`'s own
  unmeasured trade-off note — a separate concern from stopping the needless duplicates at the source).

## Done when

- [ ] The sweep does not re-publish `OperatorPresenceLost` for an operator for whom one is already
      in-flight / recently published, across Worker replicas.
- [ ] A truly missed disconnect (no recent Lost) is still caught by the sweep.
- [ ] Test proves the dedup and the still-fires-after-TTL behaviour.
- [ ] `dotnet format` / build (0 warnings) / full test suite green, counts reported.
