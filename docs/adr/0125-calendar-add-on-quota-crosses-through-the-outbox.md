# ADR-0125: The calendar add-on's quota crosses products through the outbox; the calendar owns enforcement and the downgrade rule

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 22

## Context

`22-07` sells a second add-on the same way `22-04`/`22-05` already unified the first two axes of this
stage: chat is where a tenant configures and pays, the calendar is where the fact is enforced. Unlike
those two items, this one is not identity or role data - it is a **number that gates a write**: how
many workers (`Worker`, one per master) a tenant's calendar may create.

Rule 8 states the constraint plainly: *"a write decision never reads a cache."* Two shapes were on the
table for where the number lives and who checks it:

1. **The calendar asks chat, synchronously, at the moment a worker is created** - a cross-product
   network call on the write path, and (per rule 8) still a cache by the time the calendar's own
   transaction commits, since the answer could go stale in the gap between the call and the commit.
2. **The number lives in the calendar's own database**, on the tenancy row `22-03` already keeps, and
   the calendar checks it inside its own transaction. Chat's role is only to keep that number current,
   propagated asynchronously.

A third question rides on top of the first: when a tenant lowers their plan below the number of workers
they already created, what happens to the excess? The item's own backlog text names three candidates
- refuse the change, deactivate the excess, or let the tenant sit over quota - and the author decided
on 2026-09-05: **deactivate the excess.** That half is settled elsewhere (the backlog item itself); this
ADR records the shape the *enforcement* takes, and the one further decision the backlog item left open
on purpose: *which* workers become the excess.

## Decision

**The calendar's `tenants` row gains a `worker_quota` column, granted by chat and enforced by the
calendar inside its own transaction, propagated by a new integration event that chat publishes without
learning what the number means.**

Concretely:

1. **A new, generic integration event - `ModuleQuantityGranted`** (`SiteId`, `ModuleKey`, `Quantity`,
   `OccurredAt`), published by chat's own outbox alongside `RoleAssignmentsChanged`. It carries no word
   of "calendar" or "master": the same opacity `ModuleKey` itself already enforces, checked by the
   existing architecture guard that scans `Ago.Chat.*` for a module-key literal. A module interprets its
   own `Quantity`; chat only publishes that it changed.
2. **A snapshot, not a delta** - the identical shape `22-05`'s own `RoleAssignmentsChanged` chose, for
   the identical reason: ordering is only guaranteed per partition key (rule 6), so a consumer applying
   "+2"/"-1" facts out of order could land on the wrong number forever with no way to notice. The event
   always carries the *current* granted quantity, which makes an at-least-once redelivery a genuine
   no-op on the receiving end.
3. **The calendar's own consumer applies the grant inside a transaction that locks the tenant row
   first**, `SELECT worker_quota FROM tenants WHERE id = @id FOR UPDATE`-shaped - the same lock-and-
   count idiom `docs/architecture/data-model.md` already documents for `OperatorInviteRedemptionRepository`'s
   seat limit, chosen over a denormalized counter (`operators.active_chats`'s own shape) because worker
   creation, like operator invitation, is rare and low-contention rather than a hot, contended path.
   Locking the tenant row *before* deciding anything is what closes the race between a grant lowering the
   quota and a concurrent worker-creation attempt: whichever transaction gets the lock first, the other
   waits and then re-reads the value the winner just wrote.
4. **The (N+1)-th worker is refused by the identical lock-and-count statement**, on the write path
   itself, inside the transaction that would have inserted the worker - never as a pre-check, and never
   by a separate scheduled sweep.
5. **Lowering the quota deactivates the excess**, never refuses the change and never leaves the tenant
   over quota. *Which* workers become the excess is a stated, predictable rule rather than row order:
   **the most recently created active workers are deactivated first**, until the active count matches
   the new, lower quota. A tenant who sorts their own worker list by "added on" can see exactly which
   ones a downgrade would cut, without reading a line of code. Deactivation, not deletion - nothing a
   shop typed is destroyed by a billing action, and a deactivated worker keeps his history
   (`Worker.IsActive`'s own pre-existing contract, unchanged by this item).
6. **Raising the quota back up does not reactivate anyone the downgrade deactivated.** A deliberate,
   named limitation, not an oversight: reactivation is a manual act available to the tenant once they
   are back under quota (the existing `PUT /workers/{id}` toggle), and auto-reactivating on an unrelated
   later grant would silently resurrect a worker the tenant may have replaced or no longer wants active.

## Consequences

- **A new table column on each side of the crossing, not a new database.** `ago-chat` gains
  `module_quantity_grants` (one row per site/module, mirroring `enabled_modules`' own shape but for a
  different, unrelated concern - "is this module wired" versus "how much of it was bought"). `ago-calendar`
  gains one column, `tenants.worker_quota`, defaulting to zero - the same "not granted until the add-on
  is bought" default a freshly-registered tenant already carries for every other entitlement.
- **A second broker consumer for `Ago.Calendar.Worker`**, alongside `22-05`'s
  `RoleAssignmentsChangedConsumer` - the same "this product now consumes an event it did not publish"
  shape, applied to a second, unrelated fact riding the identical mechanism (one outbox, one broker
  connection, already deploy-configured).
- **Two commits, not one, on the calendar's own consumer path** - a deliberate deviation from
  `RoleAssignmentsChangedConsumer`'s single-transaction "stage, then combine with the inbox record"
  shape. Applying a grant needs a `FOR UPDATE` lock held across a read-decide-write sequence (closing
  the race named in Decision point 3), which a stage-only port cannot express without also handing the
  Worker host a full unit-of-work abstraction this product does not otherwise have. The grant-application
  port therefore opens, uses and commits its own transaction; the inbox record is a second, separate
  save. This is safe only because the grant is naturally idempotent on its own (Decision point 2) - a
  crash between the two commits leaves, at worst, a harmless re-application on redelivery, never a wrong
  one. `messaging.md`'s own words: "either defence alone would already be enough."
- **Manual reactivation is not quota-gated by this item.** A tenant who manually reactivates a worker the
  downgrade rule deactivated (`PUT /workers/{id}`) is not stopped by this ADR's own mechanism - the
  existing endpoint predates this item and this item does not touch it. Named here as a real,
  un-closed gap rather than left to be discovered: closing it would mean the same lock-and-count check
  guarding creation also guards reactivation, and is not scoped into this change.
- **No console screen exists yet for a tenant to grant or see their own quota.** `GrantModuleQuantity`
  (chat) ships as an Application-layer command with no HTTP endpoint - the identical, already-accepted
  gap `EnableModuleForSite` shipped with before any endpoint existed for it. The settings-screen checkbox
  this item's own backlog text describes (`[ ] Master calendar for [ N ] masters`) is not built by this
  change.
- **Payment is out of scope, named rather than half-built.** This item does not touch YooKassa, seats,
  or the billing-subscription lifecycle - `GrantModuleQuantity` is the mechanism a future checkout
  confirmation would call, the same way `EnableModuleForSiteHandler` already exists independent of any
  particular caller. "Payment succeeded, provisioning did not" is `22-08`'s own tenant-lifecycle/
  reconciliation problem, not solved here.

## Alternatives considered

- **The calendar asks chat synchronously at write time.** Rejected for the reason rule 8 and this item's
  own backlog text already give: a cross-product network call on the write path, and still a cache by
  the time the calendar's own transaction commits.
- **A denormalized `active_worker_count` counter on `tenants`, updated by an atomic
  `UPDATE ... WHERE ... < worker_quota`** - the identical shape `operators.active_chats` uses. Rejected
  on the same contention-profile ground `data-model.md` already gives for choosing a lock over a counter
  for `OperatorInviteRedemptionRepository`'s own seat limit: worker creation is rare (at most a handful
  of calls ever per tenant), not the high-frequency contended path a denormalized counter exists to
  serve, and a counter would need its own symmetric decrement on every deactivation - a second write path
  with its own chance to drift from the truth, for a case that does not need the throughput a lock would
  cost.
- **Bundling the granted quantity onto `EnabledModule`** (the existing "site X has module K enabled" row)
  rather than a new type. Rejected: `EnabledModule`'s own lifecycle (entry point, trigger words,
  credential, owner-grant/expiry) is about *whether and how* a module is reachable, a different and
  independently-changing concern from *how much* of its own countable dimension has been bought. Folding
  the two would mean a credential rotation or an owner's trial grant touching a field neither has
  anything to do with, and `EnabledModule`'s own re-registration gap (no enforced one-row-per-module
  uniqueness) would become this feature's problem too.
- **Picking the excess by row order (oldest-row-id, insertion order) instead of a stated rule.** Rejected
  outright, per the backlog item's own instruction: choosing by row order is choosing for the tenant,
  invisibly. The "most recently created first" rule was chosen over its mirror ("oldest first") because
  it matches the plainest reading of what a downgrade should feel like to a shop owner - the workers who
  were around when the plan supported them keep working; the ones added most recently are what shrank
  the roster back down.
