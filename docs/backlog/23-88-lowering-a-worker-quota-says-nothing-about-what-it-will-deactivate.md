# lowering a worker quota says nothing about what it will deactivate

- **Stage**: 23
- **Status**: ready
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
  boundary that already exists, or the screen cannot honestly state it — that constraint is the whole
  design problem in this item and it should be settled before any UI is drawn.
- **Decide what deactivation means, and write it down.** Is a worker above the quota deleted,
  suspended, or merely unable to be assigned? `22-08` is the neighbouring question for tenants and
  `adr/0031`'s retention reasoning is the nearest precedent — a downgrade that destroys nothing.

## Where this is likely to go wrong

- **A confirmation dialog is not the mechanism.** If the count is computed in the browser and the write
  is unguarded, two owners acting at once still produce a surprise. Whatever states the consequence
  must be what the write consults.
- **The number can change between the statement and the write.** Say whether that is tolerated or
  rejected, rather than discovering it.

## Done when

- [ ] Lowering a quota states how many workers exceed the new number before it is applied.
- [ ] What happens to those workers is decided and written down, not left to the reader.
- [ ] The count crosses the product boundary the way `adr/0093` allows, or the item says why it cannot.
