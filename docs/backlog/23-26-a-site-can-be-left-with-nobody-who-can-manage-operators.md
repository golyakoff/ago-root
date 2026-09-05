# a site can be left with nobody who can manage operators

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-22` built the removal path this guards; the guard is additive to it.
- **Found**: 2026-09-05, while verifying `23-22`. Filed under CLAUDE.md rule 14 — a defect found
  inside an item's implementation gets its own number rather than being carried inside it.

## Goal

A tenant cannot reach a state where nobody at their site can manage operators, because the person who
could has just removed themselves.

## What is actually wrong today, verified

`RemoveOperatorHandler` makes exactly three checks, in this order:

| Check | What it refuses |
|---|---|
| `site:manage_operators` on the caller | somebody without the right |
| target exists on this site | a wrong or foreign id |
| `target.RemovedAt is null` | a double removal |

**There is no fourth.** Nothing compares the target to the caller, and nothing counts what is left
afterwards. A site whose single manager removes themselves has no operator with
`site:manage_operators`, and no path in the product that grants it back: granting is itself gated on
the permission that no longer exists anywhere on that site.

The recovery is a platform owner acting on the tenant's behalf, which makes this a support incident
rather than a mistake somebody can undo — and it is reachable by one click on a screen `23-22`
shipped for exactly this purpose.

## The invariant, stated precisely — it is not "you cannot remove yourself"

**Self-removal is legitimate.** An operator who leaves the company and takes themselves off the site
is doing the right thing, and a rule forbidding it would make the common case need a colleague.

The real invariant is one line: **at least one operator with `site:manage_operators` remains, not
removed.** Self-removal only becomes a problem as an instance of it. Writing the guard as "you cannot
remove yourself" would refuse the legitimate case and still permit the broken one — a manager
removing the *other* manager, then being removed by a platform owner's cleanup, or two managers
removing each other in either order.

## Scope

- One check in `RemoveOperatorHandler`, after the existing three: the removal is refused when the
  target holds `site:manage_operators` and is the last non-removed operator on the site who does.
- **The count is taken inside the write's own transaction, never from a cache** — CLAUDE.md rule 8,
  and this is the textbook case: a compare-and-set read that a write decision depends on. Two
  concurrent removals of the last two managers is exactly the race, and a cached count makes both
  succeed.
- A refusal a person can act on. It says a site must keep someone who can manage operators, and what
  to do — grant the permission to somebody else first. `flows.md`'s rule about error wording applies:
  it is read by a shop owner, not an engineer.
- Whatever port the count needs is declared in `Application/Abstractions` and implemented in
  `Infrastructure.Postgres`, like every other one.

## Out of scope

- **Any change to how permissions are granted.** This item refuses a removal; it does not build a
  path back from a site already in the broken state. If a tenant is in it today, that is a support
  action and stays one.
- **The same invariant for the platform-owner role.** A different scope with a different blast radius
  and its own reasoning; if it is missing too, it is its own item.
- **Removal from the console's side.** The API refuses and the console shows the refusal through the
  path it already uses for a refused write. No new screen, no new string.

## Done when

- [ ] Removing the last operator with `site:manage_operators` is refused, whether the caller is the
      target or somebody else.
- [ ] Removing a manager while another manager remains still succeeds — the legitimate case is
      untouched, and a test says so, because a guard that over-refuses is the likelier bug here.
- [ ] The count is read inside the transaction. A test proves two concurrent removals of the last two
      managers leave one standing, on real Postgres with two real connections — the assertion in this
      item that is worthless as anything but a demonstration.
- [ ] The refusal message names the situation and the way out.
