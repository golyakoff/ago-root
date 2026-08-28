# Subscription lifecycle: renewal, failure, cancellation, and mid-cycle changes

- **Stage**: 13
- **Status**: ready — the four policy questions were answered 2026-08-25 (`ago-business`'s
  `decisions/0006`), and this file's own Scope/Done-when were fleshed out 2026-08-28 (they had stayed
  "not yet defined" for three days after the policy landed — the actual blocker by then was that nobody
  had gone back to convert decided policy into a checkable Scope, not that anything was still undecided)
- **Depends on**: `13-02-yookassa-subscription-checkout-and-webhook.md` (the stored `payment_method_id`,
  the `BillingSubscription`/`billing_webhook_events` shape, and the checkout/webhook mechanism this
  item's recurring-charge job and cancellation/mid-cycle endpoints all extend rather than duplicate)

## Goal

Once this item's open questions are answered, it builds everything that happens to a subscription
*after* the first successful payment `13-02` already handles: the recurring monthly re-charge against the
stored `payment_method_id`, what happens when that charge fails, what happens when a site explicitly
cancels, and what happens when a site changes its seat count mid-cycle. None of this is built yet, and
none of it *can* be built correctly without the author's decision on each question below — this is not
missing implementation effort, it is missing policy. Writing a plausible-sounding default for any of them
would be exactly the failure mode `CLAUDE.md` warns against for a portfolio project a reviewer will read
as evidence of how the author thinks: a real business would need these stated and deliberate, not guessed.

## Context to read first

`docs/backlog/13-02-yookassa-subscription-checkout-and-webhook.md` in full — the checkout/webhook
mechanism, the `payment_method_id` this item's recurring job charges against, and the local
pending/succeeded/failed state shape this item extends with whatever additional states its own policy
answers require (e.g. `past_due`, `canceled` — not decided here, see Open questions).
`docs/architecture/resilience.md`'s "Where each boundary is, and what protects it" table and its
"Patterns we deliberately do not use" section — a recurring-charge job calling ЮKassa is exactly the
"boundary with something that can fail independently of us" shape this document already has a vocabulary
for (timeout, retry, circuit breaker where a fallback exists); whichever policy the author picks below,
its *mechanical* implementation reuses `Ago.Platform.Resilience` (`6-01`) rather than inventing new retry
machinery. `docs/architecture/messaging.md`'s outbox/dispatcher pattern — if the chosen policy involves a
scheduled recurring-charge job (near-certain regardless of which answer below is picked), it runs in
`Ago.Chat.Worker` alongside `2-06`'s `PartitionMaintenanceJob` — a `PeriodicTimer`-driven background job is
already a proven shape in this codebase, not a new one to design.

## The questions, none of which are answered anywhere in this repository or in the business context this
stage was planned against

- **Failed recurring charge**: when a scheduled re-charge against the stored `payment_method_id` fails
  (card expired, insufficient funds, ЮKassa declines), what happens? Candidates a real business would
  choose between, named for concreteness, not as a recommendation — this item takes no position:
  - Immediate downgrade to free the moment a charge fails.
  - A grace period (some number of days) during which the paid tier's entitlements still apply while
    retries continue, before downgrading.
  - A retry/dunning schedule — how many attempts, what backoff, whether the site is notified between
    attempts (and if so, how — this codebase has no email-sending infrastructure anywhere, `10-01`'s own
    explicit deferral; a notification story would need one, itself new scope).
  None of these is named in `roadmap.md`, and the business context given for planning this stage does not
  answer it either — it names ЮKassa's autopay *mechanism* as decided, not what this system does when that
  mechanism reports failure.
- **Explicit cancellation**: when a site cancels, does the paid tier's entitlements end immediately, or
  does the site keep paid-tier access until the period it already paid for ends (the common "paid until
  period end" SaaS convention, but a convention is not a decision this project has made)? This also
  determines whether a cancellation needs its own scheduled "downgrade at period end" job, or is a single
  immediate write.
- **Mid-cycle upgrade/downgrade**: if a site raises or lowers its seat count partway through a billing
  period, does the new price apply immediately with a prorated charge/credit for the remainder of the
  period, or does the change take effect at the next renewal with no proration? This also determines
  whether `13-02`'s checkout-session endpoint needs a second, different code path for "change an existing
  subscription" versus "create a new one" — a real design fork this item cannot size until the proration
  question is answered.
- **Downgrade below current operator count**: if a site's live operator count exceeds the seat count it is
  downgrading to (e.g. 5 operators, downgrading from Growth to Starter's 3-seat ceiling), what happens?
  Candidates named for concreteness only: block the downgrade until the site removes operators itself (but
  `13-01` explicitly named "remove an operator" as an unbuilt flow — this would create a dependency on
  scope that does not exist yet); let the downgrade proceed and simply block *new* invites until the count
  is back under the new limit (no existing operator is forcibly removed); something else. Not decided.

## Scope

### Recurring charge and failure handling

- A `Ago.Chat.Worker` job (`PeriodicTimer`/`BackgroundService`, `2-06`'s established shape), one tick per
  subscription whose `current_period_end` has passed, charging ЮKassa's charge-on-file API against the
  stored `payment_method_id` (`BillingSubscription`, `13-02`), wrapped in `Ago.Platform.Resilience`
  exactly as `13-02`'s own outbound calls are — no new retry machinery.
- `BillingSubscription` gains `past_due` (extending `13-02`'s `pending|succeeded|failed`) and a
  `current_period_end` column (`13-02` did not need one — a first payment has no prior period to
  measure from; a recurring one does). `sites.tier`/`seat_limit` are **not** touched on entry into
  `past_due` — `decisions/0006`'s "full access retained" means the site's own entitlements stay exactly
  as they are; only the subscription row's own status changes.
- Retry schedule inside the `past_due` window: **daily retries for 7 days** — this item's own stated
  default for `decisions/0006`'s "roughly a week," not a measurement (`CLAUDE.md`). On the 7th day with
  no success, the same write path `13-02`'s webhook applier already uses for a tier change downgrades
  the site to `tier='free'`/`seat_limit=1` — reused, not reinvented.
- A successful recharge inside the window clears `past_due` back to `succeeded` and advances
  `current_period_end` by one billing period (append-only history: this item does not decide whether
  each cycle gets its own `BillingSubscription` row or the existing row is updated in place — implementer's
  call, state which once built).

### Cancellation

- `POST /api/v1/sites/{siteId}/billing/subscriptions/{id}/cancel` (`RequireOperatorIdentity` +
  `Permission.SiteConfigure`, the same permission `13-02`'s checkout endpoint already uses for a
  billing/tier decision) sets a flag the recurring-charge job checks before attempting any charge — a
  cancelled subscription is skipped at its next `current_period_end` rather than charged and refunded.
  `sites.tier`/`seat_limit` stay exactly as paid until that `current_period_end` passes, at which point
  the same free-tier write path used for a lapsed `past_due` applies. No refund, matching `decisions/0006`
  exactly.

### Mid-cycle seat-count change

- **Upgrade**: a new endpoint (or `13-02`'s checkout-session endpoint gains a second code path for "change
  an existing subscription" — implementer's call, state which) computes the prorated difference for the
  remainder of the current period (`(new_price - old_price) × remaining_days / period_length_days`,
  rounded per whatever rule ЮKassa's own charge API expects — state it), charges it immediately against
  the stored `payment_method_id`, and updates `sites.tier`/`seat_limit` immediately on success — the
  identical "verified webhook success, not the redirect alone" discipline `13-02` already established, not
  a shortcut for being a second charge on an existing customer.
- **Downgrade**: recorded against the subscription row (a `pending_seat_count`/`pending_tier` column, or
  equivalent — implementer's call) and applied by the recurring-charge job at the next
  `current_period_end`, with no proration and no immediate write to `sites.tier`/`seat_limit`. If the
  live operator count exceeds the new, lower `seat_limit` at the moment the downgrade actually applies,
  the site enters the over-seats condition below — the downgrade itself is never blocked by operator
  count, per `decisions/0006`'s own rejection of that alternative.

### Seat assignment and operator removal — the piece `13-01` named but did not build

`decisions/0006`'s over-seats behaviour ("nothing is deleted... only the owner and as many operators as
are paid for can sign in, and the owner decides which") needs a real mechanism, and nothing in this
codebase has one yet. Two distinct capabilities, both required, neither optional:

- **Seat assignment**: `Operator` gains a `HoldsSeat` flag (default `true` at creation, since every
  operator created today is created within `13-01`'s own seat-limit check and therefore already fits).
  A console surface lets the site's `Permission.SiteManageOperators` holder toggle which operators, up
  to the current `seat_limit`, hold a seat. `OperatorIdentityClaimsTransformation` (`adr/0022`) gains one
  more condition: a real `operators` row whose `HoldsSeat` is `false` resolves to no `OperatorId` claim —
  the exact same shape as no row at all, so `RequireOperatorIdentity` already refuses it without any new
  policy code. State this explicitly wherever it lands, since it is a real behavioural change to an
  already-shipped resolution path, not a new one.
- **Operator removal**: a genuine "this person is gone" action (`POST
  /api/v1/sites/{siteId}/operators/{operatorId}/remove`, same `Permission.SiteManageOperators` gate
  `13-01`'s invite generation already uses), setting `Operator.RemovedAt`. A removed operator: is
  permanently excluded from `seat_limit`'s live count (**`13-01`'s own
  `OperatorInviteRedemptionRepository`'s `COUNT(*) FROM operators WHERE site_id = @siteId` needs
  `AND removed_at IS NULL` added — a real, necessary change to already-shipped code, named here so it is
  not rediscovered as a surprise**), is blocked from sign-in the same way a seat-less operator is, and has
  their currently-`Assigned` conversations released back to `Waiting` (reuse
  `OperatorConversationReleaser`'s existing release logic, or a narrowly-scoped variant of it — this is
  not `16-02`'s erasure job: nothing about the operator's own history, past messages, or account data is
  touched, matching `decisions/0006`'s "all its data stay intact").
- **Over-seats condition**: `count(operators where HoldsSeat AND RemovedAt IS NULL) > seat_limit` — a
  **derived condition, computed at read time, not a stored flag** (this item's own "Consequences" section
  already named this as the implementation choice, not a policy one; a stored flag would need its own
  invalidation path for no benefit, the same reasoning `13-01`'s row-lock-vs-shadow-counter note gives for
  a different, low-frequency check). Surfaced to the console so the owner sees "N of M seats assigned"
  and can act.

## Out of scope

- The multi-identity/multi-site loophole (`13-01`) and attachment/history/site-count caps (`13-05`) — both
  named, both separately blocked, neither is this item's question to resolve.
- Refunds — a related but distinct policy question this item does not fold in; real, separate scope if
  ever wanted.
- Email notification of a `past_due` charge, a cancellation, or a removal — this codebase has no
  email-sending path for anything operator-facing yet (`10-05` only covers Keycloak's own registration/
  reset flows); a real, separate item if ever wanted, not built speculatively here.
- Any UI polish beyond the minimum surface the Done-when items below require — `13-04`/`11-05`'s job,
  matching `10-03`'s own precedent for deferring visual design to the pass built for it.
- A second `BillingSubscription` row per renewal cycle versus updating one row in place — implementer's
  call, not a policy question worth blocking on.

## Done when

- [ ] A subscription whose recurring charge fails enters `past_due` with `sites.tier`/`seat_limit`
      unchanged — proven live against a fake ЮKassa host returning a decline, not asserted from the
      handler's logic alone.
- [ ] A `past_due` subscription that succeeds on a later retry (within the 7-day window) clears back to
      `succeeded` and the site's entitlements were never interrupted.
- [ ] A `past_due` subscription with no successful retry after 7 days downgrades the site to
      `tier='free'`/`seat_limit=1` — proven by advancing the clock past the window in a test, not by
      asserting the job's own retry-count logic.
- [ ] Cancelling a subscription lets the paid tier run until `current_period_end`, then downgrades — a
      cancelled-and-not-yet-expired subscription is confirmed to skip the recurring charge entirely (no
      charge attempt, successful or otherwise, reaches the fake ЮKassa host after cancellation).
- [ ] A mid-cycle upgrade charges the prorated difference immediately and updates
      `sites.tier`/`seat_limit` on the same verified-webhook discipline `13-02` established — proven with
      a real prorated amount computed against a real `current_period_end`, not a fixed test fixture.
- [ ] A mid-cycle downgrade makes no immediate charge and no immediate write, and is confirmed applied
      only once `current_period_end` passes.
- [ ] A downgrade that would drop `seat_limit` below the live operator count is not blocked — proven by
      completing one, and by then confirming the site enters the over-seats condition rather than the
      downgrade being refused.
- [ ] An operator whose `HoldsSeat` is toggled off cannot sign in (a token that previously resolved to a
      real `OperatorId` claim resolves to none) — proven with a real token against the real
      `OperatorIdentityClaimsTransformation` path, not asserted from the flag alone.
- [ ] Removing an operator: excludes them from `13-01`'s own seat-count check (a site at its `seat_limit`
      can redeem a new invite immediately after removing one existing operator, in the same test) — the
      exact regression `13-01`'s `COUNT(*)` query needs guarding against once this item lands — blocks
      their sign-in permanently, and releases their `Assigned` conversations back to `Waiting`, each
      proven with a real second call/token, not asserted from the handler's logic alone.
- [ ] The over-seats condition (`assigned-seat count > seat_limit`) is computed correctly under a
      realistic concurrent scenario (a downgrade landing at the same moment as an operator toggling
      another operator's seat) — proven, not asserted from the query looking right.
- [ ] `adr/0072` (or the next free number at time of writing — confirmed against `docs/adr/README.md`
      before use, since `13-02`'s own worker found the number this item's earlier draft assumed,
      `adr/0025`, was already taken) records the four `decisions/0006` policies and the seat-assignment/
      operator-removal mechanism, matching `13-01`/`13-02`'s own rigor.
- [ ] `docs/architecture/data-model.md` gains `BillingSubscription`'s new `past_due`/`current_period_end`
      shape, `Operator.HoldsSeat`/`RemovedAt`, and a note on the over-seats derived-condition choice.
- [ ] `docs/architecture/authorization.md` notes the sign-in-blocking behaviour added to
      `OperatorIdentityClaimsTransformation`.

## The policy, decided 2026-08-25

Recorded in full, with reasoning, in the private `ago-business` repository as
`decisions/0006`. Restated here because an item a session picks up must be buildable from this file.

**A failed recurring charge** puts the subscription in `past_due` with **full access retained** while
retries run for roughly a week; if none succeeds, the account drops to Free. The commonest cause of a
declined charge is a reissued or expired card rather than a refusal to pay, and this is a support
product — cutting a shop off on the first failure darkens its line to its own customers, who did
nothing. The exact retry schedule inside that window is this item's own choice; state it when built.

**An explicit cancellation** turns off auto-renewal and leaves the paid tier running until the end of
the period already paid for. No refund. Mechanically a flag the recurring-charge job honours.

**A mid-cycle change** is asymmetric on purpose: **upgrades apply immediately** and the difference for
the remainder of the period is charged at once; **downgrades apply at the next renewal**, with no
credit for unused time. This removes credit accounting entirely — ЮKassa has no balance concept, so a
refund-the-difference policy would mean building and reconciling our own. The asymmetry costs the
customer nothing: an upgrade is wanted *now* because someone was hired today, while a downgrade
deferred simply means keeping the tier already paid for until it lapses.

**More operators than paid seats** puts the account in an over-seats state in which **nothing is
deleted and nobody is chosen for the customer**: every operator account and all its data stay intact,
but only the owner and as many operators as are paid for can sign in, and the owner decides which.
Both rejected alternatives are worse in kind rather than in degree — disabling "the newest" or any
other rule means making an arbitrary decision about somebody else's staff, and a person loses access
mid-shift because an owner pressed a button; allowing the downgrade while merely blocking new invites
means charging for fewer seats than are in use, which retires per-seat pricing as a concept.

**This last one is one behaviour covering two paths, and that is the reason it is shaped this way.**
The same collision arises without any downgrade at all: an account that drops to Free after a failed
payment has one seat and may have six operators. There, "do not apply it until the customer complies"
is impossible — they are not answering, which is why the charge failed. Some automatic behaviour is
unavoidable, so the only real question was whether it destroys anything. This one does not.

## Consequences for other items

- **Seat assignment and operator removal, folded into this item's own Scope above (2026-08-28)** —
  originally named here as a dependency on `13-01`, but `13-01` shipped without them (its own Out of
  scope named exactly this gap) and nothing else in the roadmap owns it, so this item builds them rather
  than waiting on a third item nobody has scoped.
- **Two new subscription states** beyond `13-02`'s: `past_due`, and the over-seats condition (a derived
  read, not a stored state — see Scope).
- **No credit or refund machinery is built.** That is a direct saving and a direct consequence of the
  mid-cycle decision.
- A Free account after non-payment keeps its history: retention class is stamped at write time
  (`adr/0031`), so returning to a paid tier restores seats, not data — the data never went anywhere.

## Open questions

None. The four that blocked this item are answered above.
