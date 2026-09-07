# a ninth integration test publishes after a fixed sleep

- **Stage**: 15
- **Status**: done (2026-09-04), `ago-chat#169`. Its shape-based search found two more instances of the
  same defect, which are `15-20`
- **Found**: 2026-09-03, by `15-17`'s own author while fixing the eight that ticket named —
  and deliberately **not** folded into it (rule 15).

## The gap

`WidgetConfigCacheInvalidationEndToEndTests.cs:98` carries the identical
`await Task.Delay(TimeSpan.FromMilliseconds(500))` before publishing. `15-17` listed eight files;
this is the ninth.

The failure mode is the one already diagnosed there: if the subscription has not landed, the messages
reach an exchange with **no queue bound to it**, RabbitMQ discards them silently, and the wait that
follows observes zero for ever.

## Why it is a separate ticket rather than a ninth line in `15-17`

`15-17` is a promise about eight named files and it lands green on its own. Adding a ninth mid-flight
would widen a ticket already in review, and — more to the point — **the discovery is itself the
finding**: the list in `15-17` was assembled by grep and was incomplete. That is worth knowing
separately from the fix.

## What it needs

Whatever `15-17` builds. `RabbitMqSubscriptionTestHelpers` will already be in the repository by the
time this is picked up, so this should be small — but check it is genuinely the same shape first, and
in particular whether this test subscribes `Competing` (a stable `{topic}.{consumerName}` queue that
can be polled by name) or `Broadcast` (a random-suffixed exclusive queue, where the observable fact is
the set of queues bound to the exchange).

**`15-17`'s own fix moved the goalposts and this should follow it there**: waiting for a queue to
*exist* watches step 1 of the four `RabbitMqEventConsumer.SubscribeAsync` performs, and the race is at
step 4. The fact to wait on is a consumer actually attached — read from the management API's
`consumer_details` array, never the scalar `consumers` field, which is populated by periodic stats
emission and is **absent, not zero**, for several seconds after a queue is declared.

## Done when

- [x] This test waits for its subscription to be observable rather than for a duration, using whatever
      `15-17` established. — `ago-chat@713635b`: `WidgetConfigCacheInvalidationEndToEndTests` now uses
      `RabbitMqSubscriptionTestHelpers`, waiting on a consumer actually attached for both of the modes
      it races (`Competing` for `SiteSettingsChanged`, `Broadcast` for `CacheInvalidated`).
- [~] A grep proves there is no tenth — the same search that missed this one, run again after the fix.
      — **the search was run, and it did not prove that; it found two more.** Deliberately by shape
      rather than by literal — `Task.Delay` with any argument, `Thread.Sleep`,
      `CancellationTokenSource(TimeSpan)` — across all 19 `Task.Delay` call sites in the project, each
      read in context. `UnreadCounterEndToEndTests` and `AttachmentThumbnailEndToEndTests` both slept
      **two** seconds rather than 500 ms, which is exactly why the original literal grep never saw
      them. They were carried out to `15-20` rather than folded in here, and are fixed on `main`
      (`ago-chat@86129d9`). Getting a non-empty answer is what the box was for. (`23-55`, 2026-09-07.)
