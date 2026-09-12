# suspending a tenant, and what a suspended tenant's visitors see

- **Stage**: 22
- **Status**: ready — **the Open questions are answered (2026-09-13)**, in dialogue with the author;
  see *Answered*, below. Narrowed 2026-09-07 from "tenant lifecycle across two databases", which was
  four promises under one number (rule 15). This file keeps suspension; erasure went to `22-30`,
  export to `22-31`, reconciliation to `22-32`. See *Where the other three went*, below.
- **Depends on**: `22-03`, `22-07`
- **Decision**: `docs/adr/0149-*` — **Proposed, not Accepted.** It settled the shape; the two-numbers
  question it left open is answered below as one owner-chosen number, not two.
- **Found**: 2026-09-03, and it was missing from this stage's first draft. Recorded because the
  omission is the informative part: suspend/delete/export is the workstream nobody writes down until
  something has already gone wrong.

## Goal

An account can be suspended, account-wide, for a duration the platform owner sets in minutes at the
moment of suspending — a reversible freeze while a suspected violation is looked into, never an
erasure. The owner sees which accounts are currently suspended, can extend one or lift it early, and a
suspension nobody extends expires on its own. Independent of that owner-chosen duration, the
calendar's own knowledge of the suspension is bounded even with the broker down — an internal
robustness property, not a second number anyone sets. Lifting the suspension (by hand or by
expiring) restores everything with no re-provisioning. Nobody who is not party to the suspension
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
(`adr/0073`) and from a revoke (`adr/0118`) — **and, since the Answered section below, distinct in
*purpose* from both too: this mechanism exists for a suspected violation, never for non-payment**,
which `adr/0073`'s downgrade already handles completely on its own. A suspension never deletes an
entitlement — the `EnabledModule` row, its credential and its entry point all stand, so lifting a
suspension is a write on the account and nothing else. The calendar learns about it through the
mechanism its three existing consumers already use, with one addition that turns a hope into a bound:
the projected row carries a `valid_until` the calendar compares against its own clock **inside the
transaction that creates a booking**, chat renews it on a short, fixed schedule for as long as the
suspension is active, and a suspension is chat declining to renew *plus* an immediate event that
brings the effect forward. That renewal cadence is an internal robustness detail, not the owner-facing
duration — the owner sets *how long the suspension itself lasts* (`suspended_until`, extendable,
liftable early); the lease merely bounds how stale the calendar's own copy of "is this account still
suspended" can get before it fails closed. The two are independent, which is what makes "one owner-set
number, plus an internal bound nobody sets" the honest description rather than the two-numbers
question this section used to leave open.

## Scope

- **Account-wide, not add-on-only.** Chat stops for new sessions (the widget degrades to nothing, its
  own already-existing silent failure mode) and operators can read but not send; the calendar refuses
  new bookings the same way. Decided this way *because* the case is enforcement, not non-payment — see
  *Answered* below for why that resolves the contradiction the two readings used to pose.
- A suspension state on the account, set and cleared by the platform owner, with the act, the actor,
  the reason and the instant recorded — the same standard `adr/0118` already holds a forced revoke to,
  and for the same reason: this is an act that later has to be justified to the person it was used
  against.
- **The owner sets the duration in minutes at the moment of suspending.** Stored as `suspended_until`
  on the account, not a fixed system constant - a suspension nobody extends lifts itself when it
  passes, the same "no manual cleanup step" property lifting it early already has.
- **A console screen listing currently-suspended accounts**, each with *extend* (push
  `suspended_until` further out) and *unblock* (lift immediately) - reversing this item's own earlier
  Out-of-scope line, now that the mechanism has a duration and a list to manage, not just an on/off
  switch a single request could flip blind.
- The lease per `adr/0149`: a `valid_until` on the calendar's own tenancy row, renewed by chat on a
  short, fixed cadence - decoupled from the owner's chosen `suspended_until`, see *The design* above -
  read inside the calendar's own booking transaction. Fail-closed when it passes.
- **What the calendar refuses, and what it does not.** Refuse: creating a new booking, from the public
  widget and from the console alike. Do not refuse: every read, the tenant's own configuration
  screens, and anything touching a booking that already exists.
- **A booking already made stands.** It is not cancelled, not hidden and not retracted. The person
  holding it is a stranger to the dispute, and cancelling their appointment to apply pressure to a
  shop is using a third party as leverage. This is the same line `22-07` already drew when it decided
  that lowering a quota deactivates workers rather than deleting them: nothing a shop typed, and
  nothing a customer was promised, is destroyed by a commercial action.
- **What the tenant sees.** The console says the account is suspended, since when, until when, and
  what to do about it. That is the entire visible effect, and it is deliberately the only one.
- **What a visitor sees: nothing new**, beyond the account-wide effect Scope's first line already
  states (no widget for a new session). A conversation already open is not cut and an inbound message
  is still accepted and stored — exactly the distinction `adr/0124` already draws between blocking and
  erasure, applied one level up.
- The internal propagation bound stated in the report and in `messaging.md`: the ordinary propagation
  time (one outbox hop — `LISTEN`/`NOTIFY` wakes the dispatcher, the 5 s `OutboxDispatcher.PollInterval`
  is the fallback, and the deployment already alerts at 60 s of outbox lag) and the guaranteed ceiling
  (the lease-renewal cadence, which holds with the broker stopped) - both about how fast the *effect*
  propagates, neither a number the owner ever sets or sees.

## Out of scope

- **Changing what a lapse does.** `adr/0073` decided that a lapsed subscription downgrades rather than
  suspends, and this item does not reopen it - confirmed by the author 2026-09-13: suspension is for a
  suspected violation, never for non-payment, so there is no case left where the two mechanisms
  compete for the same trigger.
- Erasure (`22-30`), export (`22-31`), reconciliation (`22-32`). A suspicion that becomes a decision to
  actually erase the account is `22-30`'s own act, a separate one from lifting or letting this expire.
- Suspending one **operator**. A different subject, a different question, and `24-04`'s territory
  rather than this one's.

## Done when

- [ ] Suspending an account stops the calendar accepting a new booking **and** stops the widget being
      served for a new chat session, proven by doing both, with the observed elapsed time in the
      report.
- [ ] **With the broker stopped**, a suspended tenant's calendar refuses a new booking once the lease
      passes — proven by stopping the broker, not by reading the code. This is the box that makes the
      bound a bound.
- [ ] The owner can set a suspension's duration in minutes, see it in a list, extend it, and lift it
      early — and a suspension nobody touches lifts itself once `suspended_until` passes, with no
      manual step.
- [ ] Lifting a suspension (by hand or by expiring) restores bookings and the widget with no
      re-provisioning, no new credential and no manual step.
- [ ] A visitor with a conversation already open on a suspended tenant's site sees no error, and their
      message is still stored.
- [ ] A booking made before the suspension is untouched by it.
- [ ] `messaging.md` carries the internal propagation numbers, and `adr/0149` moves to Accepted with
      them filled in.

## Answered, 2026-09-13

In dialogue with the author, both questions this section used to pose resolved into one clean answer
rather than a split:

- **What is suspension for?** A suspected violation (`decisions.md` §6's own motivating case) — never
  non-payment, which `adr/0073`'s downgrade already handles completely. The author, verbatim: *«давай
  тогда зафиксируемся что приостановка у нас для нарушителей, Я не вижу необходимости что-то
  приостанавливать в течение 24 часов для штатной ситуации»* - there is no commercial-lever case left
  to design a second lease around, so the "both, with two leases" reading this section used to name is
  moot, not chosen against.
- **Is it suspension or erasure?** Confirmed suspension - a reversible freeze while a suspected
  violation is looked into, not a decision to erase. If a suspicion becomes a decision to actually
  delete the account, that is `22-30`'s own act, entered separately.
- **Account-wide or add-on-only?** Account-wide. With the commercial case gone, `adr/0073` no longer
  has anything to contradict, and add-on-only would leave this item unable to answer its own motivating
  case - a tenant using chat alone.
- **How long is the lease?** Not a fixed number at all - the author wants to set it per suspension, in
  minutes, at the moment of blocking, with a list of currently-suspended accounts to extend or unblock
  from. That single owner-facing number replaces both the "24 hours" and "minutes" this section used to
  weigh against each other; the internal lease-renewal cadence `adr/0149` still needs is a robustness
  detail underneath it, not a second thing anyone sets - see *The design* above.

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
