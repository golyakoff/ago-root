# suspending a tenant, and what a suspended tenant's visitors see

- **Stage**: 22
- **Status**: ready — **narrowed 2026-09-07 from "tenant lifecycle across two databases"**, which was
  four promises under one number (rule 15). This file keeps suspension; erasure went to `22-30`,
  export to `22-31`, reconciliation to `22-32`. See *Where the other three went*, below.
- **Depends on**: `22-03`, `22-07`
- **Decision**: `docs/adr/0149-*` — **Proposed, not Accepted.** It settles the shape; the two numbers
  it does not settle are this item's own Open questions.
- **Found**: 2026-09-03, and it was missing from this stage's first draft. Recorded because the
  omission is the informative part: suspend/delete/export is the workstream nobody writes down until
  something has already gone wrong.

## Goal

An account can be suspended. Within a bound this item states — two numbers, one for the ordinary case
and one that holds when the broker is down — the calendar stops accepting new bookings for it. Lifting
the suspension restores everything with no re-provisioning. Nobody who is not party to the suspension
notices it happened.

## What is actually true today, verified 2026-09-07

- **Nothing suspends anything.** The only `suspend`-shaped concept in `Ago.Chat.*` is `24-10`'s
  conversation blocking (`BlockConversationHandler`, `Conversation`), which is a tenant suspending
  processing for *one person* — a different subject and a different act.
- **Non-payment is already decided, and the answer is not suspension.** `adr/0073`: a failed recharge
  moves the subscription to `PastDue` with *entitlements untouched* for seven days, then to `Lapsed`,
  which downgrades the site to `tier='free'`/`seat_limit=1`. A downgrade, not a stop.
- **The lapse path does not touch modules at all.** `SubscriptionRenewalApplier`/`MarkLapsed` never
  write `EnabledModule` or `ModuleQuantityGrant`, and the only publisher of `ModuleQuantityGranted` is
  `GrantModuleQuantityHandler`. **So a tenant whose subscription lapses keeps the calendar add-on and
  its full worker quota, indefinitely.** That is true today, on the live deployment, and it is the
  concrete version of the problem this item exists for.
- **Three documents already say this item has to exist**, each declining to decide it: `decisions.md`
  §6 ("Suspending a tenant is a different action and would need its own item"), `adr/0118`
  ("Suspending a tenant remains undecided… this ADR does not narrow that question"), and `23-13`'s own
  Out of scope. This is where that question lands.
- **The propagation machinery exists three times over and carries no liveness bound.**
  `Ago.Calendar.Worker` holds `RoleAssignmentsChangedConsumer` (`22-05`), `ModuleQuantityGrantedConsumer`
  (`22-07`) and `ContactVisibilityChangedConsumer` (`23-12`) — each a snapshot event, chat's outbox to a
  calendar-local row read inside the calendar's own transaction (rule 8). Every one of them is
  *eventually* consistent with no stated ceiling, because for a permission or a quota "late" is
  survivable. For suspension it is not: late means a suspended tenant keeps taking bookings, and the
  later it is the more it takes.
- **`adr/0098` decided the opposite of what this item needs, deliberately and for its own case**: a
  grant's `ExpiresAt` "binds chat only. **The module is never told.**" That holds for a trial lapsing;
  it cannot hold for a suspension, and `adr/0149` is where the two are reconciled rather than one
  quietly contradicting the other.
- **A visitor already sees nothing when the widget cannot start.** `ago-widget/src/errors.ts` wraps
  every entry point so an internal failure "degrades to *no widget*, never to a broken site". Nothing
  has to be built for a suspended tenant's visitors to be spared an error message; something would
  have to be built for them to see one.

## The design, in one paragraph

Suspension is a state on the account with its own act and its own reversal, distinct from a lapse
(`adr/0073`) and from a revoke (`adr/0118`). A suspension never deletes an entitlement — the
`EnabledModule` row, its credential and its entry point all stand, so lifting a suspension is a write
on the account and nothing else. The calendar learns about it through the mechanism its three existing
consumers already use, with one addition that turns a hope into a bound: the projected row carries a
`valid_until` the calendar compares against its own clock **inside the transaction that creates a
booking**, chat renews it on a schedule, and a suspension is chat declining to renew *plus* an
immediate event that brings the effect forward. That is `adr/0149`, and it is why the answer to "what
is the staleness bound" is two numbers rather than one.

## Scope

- A suspension state on the account, set and cleared by the platform owner, with the act, the actor,
  the reason and the instant recorded — the same standard `adr/0118` already holds a forced revoke to,
  and for the same reason: this is an act that later has to be justified to the person it was used
  against.
- The lease per `adr/0149`: a `valid_until` on the calendar's own tenancy row, renewed by chat at
  half the lease length, read inside the calendar's own booking transaction. Fail-closed when it
  passes.
- **What the calendar refuses, and what it does not.** Refuse: creating a new booking, from the public
  widget and from the console alike. Do not refuse: every read, the tenant's own configuration
  screens, and anything touching a booking that already exists.
- **A booking already made stands.** It is not cancelled, not hidden and not retracted. The person
  holding it is a stranger to the dispute, and cancelling their appointment to apply pressure to a
  shop is using a third party as leverage. This is the same line `22-07` already drew when it decided
  that lowering a quota deactivates workers rather than deleting them: nothing a shop typed, and
  nothing a customer was promised, is destroyed by a commercial action.
- **What the tenant sees.** The console says the account is suspended, since when, and what to do
  about it. That is the entire visible effect, and it is deliberately the only one.
- **What a visitor sees: nothing new.** A conversation already open is not cut and an inbound message
  is still accepted and stored — exactly the distinction `adr/0124` already draws between blocking and
  erasure, applied one level up. A new session on a suspended tenant's page gets no widget, which the
  widget already degrades to silently.
- Both numbers stated in the report and in `messaging.md`: the ordinary propagation time (one outbox
  hop — `LISTEN`/`NOTIFY` wakes the dispatcher, the 5 s `OutboxDispatcher.PollInterval` is the
  fallback, and the deployment already alerts at 60 s of outbox lag) and the guaranteed ceiling (the
  lease length, which holds with the broker stopped).

## Out of scope

- **Changing what a lapse does.** `adr/0073` decided that a lapsed subscription downgrades rather than
  suspends, and this item does not reopen it. If the answer to the first Open question below is that a
  lapse should suspend the add-on, that is a second item and it supersedes `adr/0073` rather than
  editing it.
- Erasure (`22-30`), export (`22-31`), reconciliation (`22-32`).
- Suspending one **operator**. A different subject, a different question, and `24-04`'s territory
  rather than this one's.
- A console screen for the platform owner to suspend from. `decisions.md` §6 already defers the
  equivalent for module grants, for a reason that applies unchanged.

## Done when

- [ ] Suspending an account stops the calendar accepting a new booking, proven by doing it, with the
      observed elapsed time in the report.
- [ ] **With the broker stopped**, a suspended tenant's calendar refuses a new booking once the lease
      passes — proven by stopping the broker, not by reading the code. This is the box that makes the
      bound a bound.
- [ ] Lifting a suspension restores bookings with no re-provisioning, no new credential and no manual
      step.
- [ ] A visitor with a conversation already open on a suspended tenant's site sees no error, and their
      message is still stored.
- [ ] A booking made before the suspension is untouched by it.
- [ ] `messaging.md` carries the two numbers, and `adr/0149` moves to Accepted with them filled in.

## Open questions

**Both are the author's, and the second one decides the first.**

- **Is a suspension account-wide, or add-on-only?**
  - *Account-wide* — chat stops too: the widget is not served for new sessions, operators can read but
    not send. The suspension is real leverage and one state means one thing. Cost: it contradicts
    `adr/0073`, which deliberately chose a downgrade over a stop for non-payment, so account-wide
    suspension only makes sense if suspension's case is *not* non-payment.
  - *Add-on-only* — chat is untouched, the calendar stops taking bookings. Much smaller blast radius,
    no contradiction with `adr/0073`, and it matches the shape of the thing being sold (the calendar is
    an add-on, `22-07`). Cost: it is not leverage over a tenant who only uses chat, so it does not
    answer `decisions.md` §6's actual motivating case — the law-breaking tenant.
  - The two are not exclusive: the state can live on the account and each product decide what it does
    with it. That is the more expensive build and the one that does not have to be revisited.

- **What is suspension *for*, and therefore how long is the lease?** These are one question.
  - *A commercial lever* (unpaid invoice, chargeback): the expensive failure is a **paying** tenant's
    bookings stopping because AGO's own broker was down. Lease long — **24 hours** is the
    recommendation, renewed at 12, so a single missed renewal expires nothing and the outbox-lag alert
    has fired eleven hours before anything breaks. A non-payer taking one more day of bookings costs
    one day of a product they already had.
  - *A stop on a law-breaking tenant* (`decisions.md` §6's case): the expensive failure is the
    opposite, and a day of continued booking is a day of continued harm. Lease short — minutes — and
    accept that a broker outage now stops paying customers.
  - *Both, with two leases*: a long one for the commercial case and an immediate, unconditional
    mechanism for the other. The honest observation is that the second case probably is not a
    suspension at all — stopping a law-breaking tenant is closer to `22-30`'s erasure path, which
    already has to reach the module and prove it did.
  - **No number can be derived from measurement here.** This deployment has no recorded broker-outage
    distribution, and inventing one would be the figure `CLAUDE.md` forbids. The argument above is
    from the cost asymmetry, which is the only honest ground available.

## Where the other three went

`22-08` was filed as one item making four promises, joined by "and" — the shape rule 15 exists for.
They were split on 2026-09-07 because each is true or false on its own and each can land with the
gates green:

| Promise | Now |
|---|---|
| Suspension takes effect within a stated bound | this file |
| Erasure removes both halves, provably | `22-30` |
| An export carries both halves or fails loudly | `22-31` |
| The two databases agree about who exists | `22-32` |

`22-32` should be built **first**, even though it is numbered last: it is two reads and a report, it
needs nothing from the other three, and it is the only one of the four that can say whether drift
already exists on the live node. `22-30` found one way it certainly does (see that file's *What is
actually true today*).
