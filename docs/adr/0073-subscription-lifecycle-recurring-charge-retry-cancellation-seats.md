# ADR-0073: Subscription lifecycle — recurring charge, retry, cancellation, mid-cycle change, and seat assignment

- **Status**: Accepted
- **Date**: 2026-08-29
- **Stage**: 13

## Context

`13-02` built the first payment: a checkout session, a verified webhook, `sites.tier`/`seat_limit`
activated once. Nothing existed past that first payment — no recurring re-charge, no handling for a
declined renewal, no cancellation, no way to change a seat count mid-cycle, and no real mechanism for
the seat-assignment/operator-removal story `13-01` named but explicitly deferred. Four policy questions
had to be answered before any of this could be built correctly, not just implemented plausibly — a
portfolio project a reviewer reads as evidence of how the author thinks cannot paper over a missing
business decision with a guessed default (`CLAUDE.md`). Those four questions were answered 2026-08-25 in
the private `ago-business` repository as `decisions/0006`, restated here in full since an ADR must be
readable without that source.

**`decisions/0006`, in full:**

A failed recurring charge puts the subscription in `past_due` with full access retained while retries
run for roughly a week; if none succeeds, the account drops to Free. The commonest cause of a declined
charge is a reissued or expired card, not a refusal to pay, and this is a support product — cutting a
shop off on the first failure darkens its line to its own customers, who did nothing.

An explicit cancellation turns off auto-renewal and leaves the paid tier running until the end of the
period already paid for. No refund.

A mid-cycle change is asymmetric on purpose: upgrades apply immediately and the difference for the
remainder of the period is charged at once; downgrades apply at the next renewal, with no credit for
unused time. This removes credit accounting entirely — ЮKassa has no balance concept, so a
refund-the-difference policy would mean building and reconciling our own.

More operators than paid seats puts the account in an over-seats state in which nothing is deleted and
nobody is chosen for the customer: every operator account and all its data stay intact, but only the
owner and as many operators as are paid for can sign in, and the owner decides which. The rejected
alternatives (auto-disabling "the newest", or letting the downgrade proceed while merely blocking new
invites) are worse in kind, not degree: one makes an arbitrary call about somebody else's staff and can
end a person's access mid-shift; the other charges for fewer seats than are in use, which retires
per-seat pricing as a concept.

**Note on this ADR's number.** The backlog item that scoped this work
(`13-03-subscription-lifecycle-policy.md`) originally assumed `adr/0072`, following `13-02`'s own
precedent of naming the next-expected number; by the time this item was implemented `0072` had already
been taken (`0072-tenant-export-format-and-attachment-reference.md`). This ADR takes `0073`, confirmed
free against `docs/adr/README.md` immediately before writing this file.

## Decision

### Recurring charge and failure handling

`Ago.Chat.Worker`'s `SubscriptionRenewalJob` (the same `PeriodicTimer`/`BackgroundService` shape as
every other sweep in this codebase) ticks hourly and asks `IBillingSubscriptionRepository.ListDueForRenewalAsync`
for every row whose `current_period_end` has passed (`Succeeded`) or whose daily retry is due
(`PastDue`). `BillingSubscriptionStatus` gains two states: `PastDue` (a recharge failed;
`sites.tier`/`seat_limit` untouched) and `Lapsed` (the terminal state reached either by exhausting the
7-day `PastDue` retry window or by a cancelled subscription reaching its own paid-through period end —
one terminal state for both, because from the site's own point of view "ran out of retries" and "chose
not to renew" end in the identical place). Retries inside the `PastDue` window run at most once per
calendar day, gated by elapsed time since `LastRenewalAttemptAt` rather than a plain attempt counter, so
the job's own tick interval is free to run more often than once a day without over-charging.

`BillingSubscription` is extended in place, not replaced by a new row per billing cycle — an
implementer's call the backlog left open, decided here because the type was already named for what it
becomes (its own remarks from `13-02`), and nothing in this item's Scope needs a queryable per-cycle
history the ledger table (`BillingWebhookEvent`) does not already give as an audit trail.

The recurring charge is a "charge on file" call (`IYooKassaPaymentsClient.ChargeStoredPaymentMethodAsync`,
no `confirmation` object, no browser involved) against the `payment_method_id` `13-02`'s first payment
already stored. Its own idempotence key is deterministic — `renewal:{subscriptionId}:{date}` for an
on-time renewal, implicitly reused across ticks for the same subscription and day — not a fresh id per
call, because the real hazard this item's own scale introduces is two `Ago.Chat.Worker` replicas
independently deciding the same row is due on the same day, not a client-side network retry. A
deterministic key turns that race into ЮKassa returning one real payment's result twice rather than two
real charges, which is cheaper and more honest than adding a row lock to a job whose own cadence (daily,
at most) does not need one.

**Branch order inside `ProcessSubscriptionRenewalHandler`, and why it is exactly this order**: `CancelRequested`
is checked first, regardless of status — `decisions/0006`'s "no charge attempt, successful or otherwise"
once cancelled, so this must gate before any charge decision, not after. Verified directly: no code path
between the `CancelRequested` check and the `ChargeStoredPaymentMethodAsync` call can return early with a
charge still pending, and a fails-before proof (disabling the check) shows a cancelled, due subscription
actually gets charged by the fake ЮKassa host instead of lapsing.

Wrapped in `Ago.Platform.Resilience` via a decorator (`Ago.Chat.Module.Billing.ResilientYooKassaPaymentsClient`
wrapping `ChargeStoredPaymentMethodAsync` in a new, unkeyed `BillingResiliencePipeline`) — the same
composition-over-inheritance shape `ResilientInboundChannelAdapter` already established for channel
adapters, chosen specifically so `13-02`'s own `CreatePaymentAsync` call (deliberately left unwrapped, a
synchronous human-driven write) is unaffected: the decorator forwards that method straight through and
only wraps the new recurring call.

### Cancellation

`POST /api/v1/sites/{siteId}/billing/subscriptions/{id}/cancel` (`RequireOperatorIdentity` +
`Permission.SiteConfigure`, the same gate `13-02`'s checkout endpoint uses) sets
`BillingSubscription.CancelRequested`, a flag the recurring-charge job checks before ever attempting a
charge — checked first, ahead of the ordinary due/retry branches, so a cancelled row reaching its period
end lapses with *no* charge attempt reaching ЮKassa, successful or otherwise, matching `decisions/0006`
exactly.

### Mid-cycle seat-count change

One new endpoint, `POST /api/v1/sites/{siteId}/billing/subscriptions/{id}/seats`, not a second code path
on `13-02`'s checkout-session endpoint — the implementer's call the backlog left open, decided in favour
of a dedicated endpoint because "change an existing subscription" shares no request/response shape with
"create a new one" (no ЮKassa redirect, no new `billing_subscriptions` row), so branching inside the
checkout handler on "does `{id}` already exist" would mean half that handler's own logic never applies to
the branch that reached it.

An upgrade (`ChangeSubscriptionSeatsHandler.ApplyUpgradeAsync`) computes
`(new_price - old_price) * remaining_days / period_length_days` — both prices from the flat
`BillingOptions.PricePerSeatRub` (this codebase's pricing has no separate per-tier price; seats are the
only variable), `remaining_days` clamped to `[0, PeriodLength]` against the subscription's own real
`CurrentPeriodEnd`, rounded to two decimal places away from zero (ЮKassa's own amount field is a
fixed-point string with exactly two fraction digits) — charges it immediately via the same charge-on-file
call the renewal job uses, and only on a verified success applies the new seat count/tier to both the
subscription row and `Site.Tier`/`Site.SeatLimit`, in one transaction
(`Ago.Chat.Infrastructure.Postgres.SeatChangeApplier`, the same "own port because it writes across more
than one aggregate" shape `BillingWebhookApplier` established for the analogous first-payment write).

A downgrade (`BillingSubscription.ScheduleSeatDecrease`) makes no charge and no immediate write at all —
it records `PendingSeatCount`/`PendingTier` on the row, applied only by the next successful
`RecordRenewalSuccess`, whether that renewal is on-time or itself a `PastDue` retry.

### Seat assignment and operator removal

`Operator` gains two columns: `HoldsSeat` (default `true` — every operator created today is created
inside `13-01`'s own seat-limit check and therefore already fits) and `RemovedAt` (`null` until a real
"this person is gone" action). Both are plain flags, not a value object — neither has any lifecycle
beyond "on or off" / "set once, never cleared", the same "one column, no object to bundle it into yet"
judgement `Site.Tier`/`Site.SeatLimit` already made for the analogous case.

The entire sign-in-blocking mechanism is two query filters, not new policy code:
`IOperatorRepository.GetByExternalSubjectIdAndSiteIdAsync`/`ListByExternalSubjectIdAsync` — the two
queries `ResolveOperatorIdentityHandler` resolves a signed-in principal through — now filter on
`HoldsSeat && RemovedAt IS NULL`. A seat-less or removed operator resolves to no row, which
`ResolveOperatorIdentityHandler` already turns into "no `OperatorId` claim added", the exact same shape
as no `operators` row ever existing — `Ago.Chat.Api.Auth.OperatorIdentityClaimsTransformation` needed no
code change at all; its behaviour changed as a consequence of the query it depends on changing under it.

`POST /api/v1/sites/{siteId}/operators/{operatorId}/seat` (`Permission.SiteManageOperators`) toggles
`HoldsSeat`. Toggling on is capacity-checked against the site's current `seat_limit` (the same `402`
vocabulary `13-01`'s own invite seat check uses); toggling off is never blocked. This is an implementer's
call the backlog left open ("up to the current seat_limit") — decided so an owner cannot manufacture a
*fresh* over-seats state by hand when the site is not already over its limit, without reopening
`decisions/0006`'s own rejection of blocking a *downgrade* on live operator count: the two are different
actions, and only the downgrade's own no-block guarantee is a decided policy.

`POST /api/v1/sites/{siteId}/operators/{operatorId}/remove` (`Permission.SiteManageOperators`) stamps
`RemovedAt` and raises `OperatorRemoved`, mapped to the outbox as `OperatorRemovedFromSite` — a real
committed state change, published through the outbox exactly like `SiteSubscriptionActivated`, not
direct-published like the presence-only `OperatorPresenceLost`. `Ago.Chat.Worker`'s new
`OperatorRemovedConsumer` reacts by calling the existing `OperatorConversationReleaser` — reused verbatim,
not reimplemented — to release the removed operator's `Assigned` conversations back to `Waiting`, out of
the removal request's own transaction, the same "state change commits, the wider consequence is a
separate, retried step" shape the outbox exists for everywhere else in this codebase.

`13-01`'s own `OperatorInviteRedemptionRepository` seat-limit `COUNT(*) FROM operators WHERE site_id =
@siteId` gains `AND removed_at IS NULL` — without it, a removed operator counted against the seat limit
forever, a real regression this item's own backlog named explicitly rather than leaving to be
rediscovered. `HoldsSeat` is deliberately not part of that filter: the invite check answers "how many
operator rows does this site have", not "how many currently hold an assigned seat" — a different question
`GetSeatAssignmentSummaryHandler` answers instead.

The over-seats condition (`count(HoldsSeat AND RemovedAt IS NULL) > seat_limit`) is a derived read,
computed at request time by `GetSeatAssignmentSummaryHandler`
(`GET /api/v1/sites/{siteId}/operators/seat-assignment-summary`) — never a stored flag. This is this
item's own Scope, not a decision made here: a stored flag would need its own invalidation path for no
benefit a plain two-query read does not already give, the same reasoning `13-01`'s own
row-lock-vs-shadow-counter note gives for a different, low-frequency check. Proven correct under a real
concurrent race — independent writes to `sites.seat_limit` and to six different operators' `HoldsSeat`
landing at the same moment — by comparing the derived read against ground-truth `COUNT(*)` after the race
settles, not by asserting the query text looks right.

## Consequences

- Two new `BillingSubscriptionStatus` values (`PastDue`, `Lapsed`) and six new columns on
  `billing_subscriptions` (`current_period_end`, `past_due_since`, `last_renewal_attempt_at`,
  `cancel_requested`, `pending_seat_count`, `pending_tier`); two new columns on `operators` (`holds_seat`,
  `removed_at`). Migration `Stage13AddSubscriptionLifecycleAndOperatorSeats`.
- A new Worker background job (`SubscriptionRenewalJob`) and a new consumer (`OperatorRemovedConsumer`),
  both following this codebase's own established shapes rather than introducing a new one.
- No credit or refund machinery exists anywhere in this codebase — a direct, intended saving from the
  mid-cycle policy's own asymmetry, not an oversight.
- A Free account after non-payment keeps its history: retention class is stamped at write time
  (`adr/0031`), so a later return to a paid tier restores seats, not data.
- `OperatorInviteRedemptionRepository`'s seat-limit check now depends on `removed_at`, a column that did
  not exist before this item — any future direct-SQL seeding of `operators` rows (demo scripts, fixtures)
  must set it `NULL`, not omit it, or the column's own `DEFAULT NULL` already covers that.
- The recurring-charge job's own correctness now rests on ЮKassa's own idempotency guarantee for a
  repeated `Idempotence-Key`, not on a database lock — a genuine dependency on the provider's own
  documented behaviour, unverified against a live credential, the same class of trust `13-02`'s own ADR
  already flags for other parts of this integration.
- `docs/architecture/tenant-isolation.md` gains one more exemption entry: `ProcessSubscriptionRenewalHandler`
  carries no `SiteId` — the job's own candidate scan is what restricts it, not a caller — the identical
  shape `AutoCloseConversationHandler` (`18-06`) is already classified under.

## Alternatives considered

- **A new `BillingSubscription` row per renewal cycle**, giving a queryable per-cycle history for free.
  Rejected: nothing in this item's Scope asks for that history, `BillingWebhookEvent` already gives an
  audit trail of every ЮKassa event, and a new row per cycle would mean `BillingSubscriptionId` no longer
  identifies "this subscription" but "this cycle" — a rename with no offsetting benefit.
- **A row lock (`SELECT ... FOR UPDATE`) serializing the renewal job's own candidate processing**, the
  same shape `OperatorInviteRedemptionRepository` uses for its seat-limit check. Rejected: the renewal
  job's own contention is low-frequency (at most one attempt per subscription per day) and the
  deterministic idempotence key already makes a genuine two-replica race safe by construction — a lock
  would add machinery to protect against a race that does not need preventing.
- **Blocking a downgrade that would exceed the live operator count**, and **letting the downgrade proceed
  while only blocking new invites** — both named and rejected in `decisions/0006` itself, not a choice
  this ADR reopens.
- **A stored over-seats flag**, invalidated by an event whenever `seat_limit` or any operator's
  `HoldsSeat` changes. Rejected: this item's own Scope already named the derived-read shape as the chosen
  mechanism, and a stored flag's own invalidation path would need to fire from at least three independent
  write paths (the renewal job's downgrade apply, the toggle-seat endpoint, the remove-operator endpoint)
  for a value a plain two-query read already computes correctly on demand.
