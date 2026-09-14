# 25-84 · A blocked tenant can pay their way back to reading files

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-83` — the hard block this item exists to lift. Building this before `25-83`
  merges would have nothing to attach a payment to.
- **Decision**: the author's, reached in dialogue with the managing session, 2026-09-14 — the same
  conversation that produced `25-83`; see that item for the enforcement half.
- **Found**: the same place `25-83` was — `23-82`'s own deferred ceiling decision, split in two once
  the shape of "what happens at the ceiling" turned out to be its own real feature, not a detail of
  enforcing the ceiling itself.

## The shape, decided 2026-09-14

**Metered, not a flat unlock.** 100 ₽ per gigabyte over the hard threshold, platform-owner
configurable (a default, not a hardcoded constant — the same per-tier-editable shape `25-83`'s own
thresholds already take, though this price is deployment-wide rather than per-tier unless the owner
says otherwise when this is built). This is real usage-based billing, not a single toggle-purchase —
say this plainly, because it changes what "metered" costs to build: the charge has to be computed
from an actual gigabyte count, not from a boolean.

**Valid until the end of the current calendar month, however little of it remains**, and does not
carry into the next month — a tenant who pays on the 28th gets three days of unblocked reading, not a
refund or a rollover credit. The counter (and the threshold itself) resets with the new month, the
same boundary `23-82`'s own `period_month` bucketing already uses.

**Paying unblocks immediately.** Whatever mechanism actually applies the charge, the tenant's next
presigned GET after payment succeeds without waiting for any billing cycle boundary.

**A platform-owner-only, per-tenant toggle decides how the charge is applied — not a tenant-facing
setting.** Two modes:
- **Auto-bill** (the recommended default, per the author's own reasoning: "planned expenses beat
  surprise ones" — a tenant would rather see this on next month's regular invoice than have to notice
  and act on a block mid-month): crossing the hard threshold auto-applies the per-GB charge as it
  accrues and keeps the tenant unblocked, with the accumulated charge appearing as a line item on
  their next regular invoice. No explicit action from the tenant at the moment of crossing.
- **Manual**: crossing the hard threshold blocks as `25-83`'s own base case describes, and the
  tenant/operator sees the same "this is limited, pay to continue" state everywhere `25-83`'s own
  block is visible (console banner, the in-conversation system message) with a real, immediate
  checkout — the same purchase mechanism this codebase already uses for a module or a seat, not a new
  payment flow invented for this one case. Paying unblocks the same way as the auto-billed path.

Both modes ultimately charge the same 100 ₽/GB meter; the toggle decides *when* the tenant commits to
paying it, not *whether*.

## Where this is likely to go wrong

- **This is the item that turns `23-82`'s own proxy egress counter into a real, disputable invoice
  line.** `25-83`'s own Done-when already asks that the proxy nature be stated rather than inherited
  silently — this item is where that stops being a footnote and starts being a number a tenant could
  reasonably ask to see justified. Decide, and state, whether the invoice line shows the raw
  gigabyte figure this meter produced, or something reconciled against the storage provider's own
  egress bill (`23-82`'s own "ours is a proxy, theirs is the truth" distinction) before this ships —
  billing off a number this codebase has already called imprecise, without saying so to the tenant,
  is the shape of dispute this item should not manufacture on day one.
- **Auto-bill accrues a debt with no natural ceiling of its own.** A tenant on auto-bill who keeps
  getting downloaded from (their own visitors, not necessarily anything they did) could accrue a large
  next-invoice charge with nothing stopping it mid-month, by design — that is the whole point of
  "unblocked." Whether the platform owner wants any secondary cap on the auto-bill path (a second,
  higher hard stop even auto-bill cannot cross) is a real question this item should ask before
  building, not assume either way.
- **The existing purchase/checkout mechanism this item reuses for the manual path was built for a
  one-time, fixed-price purchase (a seat, a module).** A metered amount computed at the moment of
  payment (how many GB over, right now) is a different shape than "buy one of these" — read that
  mechanism's own code before assuming it takes a variable amount without a change of its own.

## Out of scope

- The block itself, both thresholds, the owner's free-override toggle, and the notification/
  in-conversation-message mechanism — all `25-83`.
- Any tenant-facing self-service control over the auto-bill/manual toggle — stays the platform
  owner's, per the decision above.

## Done when

- [ ] The per-GB overage price is configurable by the platform owner, not hardcoded, with 100 ₽ as
      the shipped default.
- [ ] A charge computed from real gigabytes-over-threshold, valid through the end of the current
      calendar month only, is provably correct against a fabricated egress figure — not merely "some
      amount was charged."
- [ ] Paying (either path) unblocks the tenant's next presigned GET immediately, proven end to end.
- [ ] The platform owner can set the auto-bill/manual toggle per tenant, and both paths are proven —
      auto-bill accrues onto the next invoice with no tenant action; manual blocks until an explicit,
      real checkout.
- [ ] Whether the invoiced figure is the raw proxy count or something reconciled is decided and
      stated, not left implicit now that it is a real money question.
