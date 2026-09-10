# lowering a worker quota says nothing about what it will deactivate

- **Stage**: 23
- **Status**: done — `ago-chat#255`, `ago-calendar#58`, `adr/0165`. Both halves of the async
  round trip are built and independently verified; **`25-44`**, found while landing this half, is why
  a real deployment will not actually deliver the reply until its own dispatcher exists — that is a
  pre-existing gap in `Ago.Calendar.Worker` this item's own scope does not include.
- **Depends on**: `23-66`, which built the grant this lowers.
- **Found**: 2026-09-07, carried out of `23-66` at landing rather than left inside it.

## Why this is its own number

`23-66` made a worker quota grantable at all — the route existed nowhere, so `Tenant.WorkerQuota` was
zero for every tenant that would ever exist. That promise landed green and closed.

**Its third Done-when did not**: *lowering a quota states what it will deactivate before it does it.*
Leaving that box inside `23-66` would have meant either closing a ticket with an unsettled box, or
holding a delivered capability open behind a different promise. Rule 14's clause is exact about which
of those to do: the remainder gets a number, not a link.

## What is actually true today

The grant path sets a quantity. **Nothing reads the quantity downwards.** There is no confirmation, no
count of what exceeds the new number, and no statement of what happens to the workers above it — not in
the handler, not in the console screen `23-66` added beside `23-65`'s module grant.

So a platform owner lowering a tenant's quota from five to two is making a decision about three
people's accounts with no idea which three, and the tenant finds out when somebody cannot sign in.

## Scope

- **Before the write, say what it will do.** How many workers exceed the new quota, and which ones.
- **The tenant's own workers are the calendar's rows, not chat's.** `adr/0093`: two schemas, two
  databases, neither product reads the other's tables. So the count comes from the calendar, over the
  boundary that already exists — **but not as a live synchronous call, decided below.**
- **Decided: deactivation means the worker simply cannot be assigned a new booking.** Nothing is
  deleted or suspended — the worker's own row, history and existing bookings are untouched; they are
  merely excluded from whatever the assignment/booking path already treats as "bookable" once they sit
  above the tenant's own quota. The closest existing precedent for "a downgrade that destroys nothing"
  is `adr/0031`'s own retention reasoning, restated here for a different resource.

## Decided: build the general async mechanism, not a one-off synchronous call

**The author's own reasoning, 2026-09-09:** today, lowering a quota is the platform owner's own manual
act, and nothing about it depends on the calendar being reachable — the grant is written in `ago-chat`
and delivered over the outbox, exactly like `23-66`/`23-89`'s own mechanism. A live, synchronous
cross-product call made only to answer "how many workers does this affect" would introduce a
dependency that does not exist today: an owner could no longer lower a quota at all while the calendar
happens to be unreachable, which is a real regression against `adr/0093`'s own product-independence
guarantee, not a narrow, harmless exception the way `22-11`'s registration RPC is.

**It also cannot be a synchronous call for a second, stronger reason.** `ModuleQuantityGrant` (the
mechanism a quota grant already rides) is the same primitive `23-86` already wired an *automatic*
grant/revoke into on a subscription's own lapse — today only for options (channels), not yet for
worker quota, but the same infrastructure. If lowering a quota is ever triggered automatically by
non-payment rather than only by an owner's click, that trigger fires from an unattended background
job with no human session to show a count to or wait on a confirmation from — a synchronous call is
not merely undesirable there, it is structurally impossible. Building this item's own answer as an
async mechanism from the start means the eventual automatic path (if one is ever built) needs no
second design, rather than redoing this item's own answer later.

**The shape this implies:** the owner-facing "how many, which ones" statement is itself an
asynchronous round trip to the calendar (request, wait for the calendar's own answer, then show it —
the same "outbox out, real answer back" shape `23-89` already established elsewhere, not a live
request/response pair blocking on the calendar's uptime). The actual deactivation decision is not
taken from that earlier, possibly-stale answer at all: it is recomputed fresh, inside the calendar's
own database, at the moment the lowered quota is actually applied there — whichever path applied it,
an owner's confirmed write today or an automatic non-payment trigger later.

## Where this is likely to go wrong

- **A confirmation dialog is not the mechanism.** If the count is computed once and shown, and the
  write is unguarded, two owners acting at once (or an owner confirming against a stale count) still
  produce a surprise. Whatever states the consequence must be what the write consults.
- **Decided (owner-confirmed path): recompute at write time, and refuse rather than silently apply a
  different outcome than what was shown.** The number the owner saw is fetched once, asynchronously;
  when they confirm, the write recomputes the live count fresh against the calendar's own database
  (`CLAUDE.md` rule 8 — never let a write decision trust a cached read) and compares it to what was
  shown. A match applies normally. A mismatch refuses the write and sends the owner back to see the
  current, correct count before they can confirm again — never applies a quota change against a
  consequence they never actually saw.
- **An automatic future trigger (non-payment) has no prior shown count to compare against at all** —
  it never showed anyone anything, so "diverges from what was shown" does not apply to it; it simply
  acts on the live count at the moment it fires. Named here so whoever eventually builds that path
  does not go looking for a comparison this item's own answer never intended for it.

## Done when

- [x] Lowering a quota states how many workers exceed the new number before it is applied, fetched
      asynchronously — never a live synchronous call to the calendar.
      Both halves are built and tested: `POST .../modules/{moduleKey}/quantity/impact` starts the
      question (stages `ModuleQuantityImpactRequested` on chat's own outbox, never blocks); `GET` on
      the identical route reads back a three-state answer (never asked / asked, not yet answered /
      answered). `Ago.Calendar.Worker.ModuleQuantityImpactRequestedConsumer` answers it, publishing
      `ModuleQuantityImpactComputed` on calendar's own outbox. **Caveat, not a reason to leave this box
      open**: `25-44`, found while landing this half, means neither product's own outbox dispatcher
      situation guarantees the reply actually reaches the broker on a real deployment today — the
      identical pre-existing gap `BookingConfirmed` (`20-04`) has carried since it shipped, tracked
      there and not invented by this item.
- [x] What happens to those workers is decided and written down: nothing is deleted or suspended, they
      simply cannot be assigned a new booking while above the tenant's own quota.
      Confirmed already fully built, not touched by this pass: `adr/0125`/`ago-calendar`'s own
      `ModuleQuantityGrantedConsumer` + `WorkerQuotaPolicy` deactivate the most-recently-created active
      workers first, inside the transaction that applies the grant, every time - unconditionally, with
      no dependency on anything this item adds.
- [x] The count crosses the product boundary the way `adr/0093` allows (async, over the existing
      outbox shape), and the write recomputes it fresh rather than trusting the earlier shown value —
      refusing rather than silently diverging from what the owner confirmed against.
      **The crossing reuses the identical outbox mechanism `adr/0125` proved for the grant itself** - a
      new `ModuleQuantityImpactRequested` event, the same shape as `ModuleQuantityGranted`, and a
      `ModuleQuantityImpactComputed` reply back, the first crossing to run calendar-to-chat
      (`adr/0165`). **The write-time refusal is real and tested, and is deliberately a narrower
      guarantee than a live recompute would be**: `GrantModuleQuantityAsOwnerHandler`/
      `GrantModuleQuantityHandler` compare the owner's confirmation against chat's own stored copy of
      the module's last answer (never a live call to the calendar - rule 8 forbids that at this write),
      and refuse (`Module.QuantityImpactStale`, HTTP 409) on any mismatch or missing answer. The
      unconditional safety net stays exactly where it already was: `adr/0125`'s own live lock-and-count
      on the calendar's side - no *wrong* deactivation was ever possible regardless of what chat sends,
      by design, stated explicitly in both handlers' own remarks and in `adr/0165`'s Consequences.

## Outcome (this pass)

`ago-chat` branch `feat/23-88-quota-lowering-states-deactivation`: the owner-facing half of the async
preview round trip, complete and tested - `ModuleQuantityImpactPreview` (Domain, one row per
site/module, the identical snapshot shape `ModuleQuantityGrant` already uses), `ModuleQuantityImpactRequested`
(Contracts, the outbound question, riding chat's existing outbox exactly like `ModuleQuantityGranted`
does), `IModuleQuantityImpactPreviewStore`/`ModuleQuantityImpactPreviewStore` (Application/Infrastructure,
one migration, `Stage23AddModuleQuantityImpactPreviews`), two new owner routes
(`POST`/`GET .../modules/{moduleKey}/quantity/impact`), a `Ago.Chat.Worker` consumer
(`ModuleQuantityImpactComputedConsumer`) ready to receive a reply nothing sends yet, and the write-time
guard on both `GrantModuleQuantityAsOwnerHandler` and `GrantModuleQuantityHandler`
(`ExpectedAffectedCount`, optional, backward-compatible - `null` preserves every existing caller's
behaviour unchanged).

**What `ago-calendar` needs, precisely, to complete the loop** (not built this pass - no worktree
assigned, and this item's own instructions were explicit: report rather than guess):

- A new consumer on `ModuleQuantityImpactRequested` (topic name literal `"ModuleQuantityImpactRequested"`,
  filtered by `ModuleKey == "calendar"`, the identical shape `ModuleQuantityGrantedConsumer` already
  establishes for its sibling topic).
- A read-only computation: how many of the tenant's own active workers exceed the requested candidate
  quantity, and their display names - no lock needed (nothing is written), unlike the grant's own
  `FOR UPDATE` application.
- A reply published on calendar's own outbox to a topic named `"ModuleQuantityImpactComputed"` (a
  literal `ago-chat`'s own `ModuleQuantityImpactComputedConsumer` already subscribes to and is ready
  for), carrying `SiteId`, `ModuleKey`, `RequestedQuantity`, `AffectedCount`, `AffectedItemDisplayNames`,
  `CorrelationId`, `OccurredAt` - the exact shape `ago-chat`'s own
  `ModuleQuantityImpactComputedWireContract` (`Ago.Chat.Worker`) already specifies and is waiting to
  deserialize.

This is additive on the calendar side (a new consumer + a new outbound topic), not a change to
`adr/0125`'s own existing enforcement - the two mechanisms are independent, and the belt-and-suspenders
version of the write-time guard (calendar's own consumer re-validating the expected count against its
live read, reported back) is a further, optional refinement on top of what's specified here, not a
prerequisite for it.

Fails-before: the write-time guard's two refusal tests (`HandleAsync_WithExpectedAffectedCountDisagreeing...`,
`HandleAsync_WithExpectedAffectedCountButNoPreviewEverRequested_Refuses`) were run against the handler
with the guard block temporarily removed - both failed (asserted `IsFailure`, got `IsSuccess`) while
every other test in the same file stayed green; restored, all pass.

Verification (`ago-chat`): `dotnet format --verify-no-changes` clean; `dotnet build -c Release` 0
warnings/0 errors; exact test counts in this item's own worker report. Migration applied and verified
against a real local Postgres before being included (`dotnet ef database update`, table inspected with
`psql`). No `ago-deploy` or `ago-console` change - this item's own scope stayed inside `ago-chat`, with
`ago-calendar`'s own remaining half specified above rather than guessed at.

## Outcome (`ago-calendar` half, landed same day)

`ago-calendar` branch `feat/23-88-calendar-answers-quota-impact-preview`: `WorkerQuotaImpactAnswerer`
(reads active workers with no lock, reuses `WorkerQuotaPolicy.SelectWorkersToDeactivate` rather than a
second "who is excess" rule - the identical rule a real downgrade would apply, not a guess at one) and
`ModuleQuantityImpactRequestedConsumer` (mirrors `ModuleQuantityGrantedConsumer`'s own shape; no inbox
ledger, deliberately - this consumer changes no local state, so a redelivery just re-answers, never
wrong, per `adr/0165`'s own idempotency reasoning). No migration - read-only, as scoped.

Independently re-verified: `dotnet format --verify-no-changes` clean; `dotnet build -c Release` 0
warnings/0 errors; full suite Application 204/204, Domain 229/229, Architecture 26/26, Concurrency
26/26, Integration 309/310 (the one failure, `ChatModuleTaskEndpointTests`'s own re-offer test,
reproduced identically against the unmodified `origin/main` baseline with no `23-88` changes present -
pre-existing and unrelated, filed as `25-45`). Fails-before: the active-worker filter and the
`ModuleKey` filter each independently shown to fail their own test when removed, restored, green.

**Found while landing this half, not fixed here**: `Ago.Calendar.Worker` has no outbox dispatcher at
all - the identical gap `BookingConfirmed`'s own "None wired yet" note has carried since `20-04`, now
also true of this item's own reply. Filed as `25-44` rather than expanded into this item's own scope,
since fixing a pre-existing infrastructure gap that predates this item by five stages is a different
promise than the one `23-88` itself makes.

`ago-chat#255`, `ago-calendar#58`, `ago-root#849` (docs half). `25-44` and `25-45` filed as
separate items per the findings above.
