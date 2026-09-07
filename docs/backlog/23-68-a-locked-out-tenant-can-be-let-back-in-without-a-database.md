# a locked-out tenant can be let back in without a database

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-67` prevents the lockout; this recovers from one. Neither replaces the other.
- **Found**: 2026-09-07, by needing it. A tenant locked itself out during a live demonstration and the
  only way back was an `UPDATE` against the live database, typed by hand.

## Why this exists even after `23-67`

`23-67` closes the route that was taken. It does not close the ones nobody has found yet, and it does
nothing for an account already in that state. **A product whose recovery path is "somebody with
database access edits a row" has no recovery path** — it has an incident procedure that happens to
work while the person who wrote the system is still answering the phone.

The first paying customers are weeks away. This is the difference between a bad afternoon and a
customer who cannot be helped.

## Scope

- **A platform owner can restore an operator's seat for any tenant**, from the console, on the tenant
  detail screen `23-65` is building.
- **It is recorded** — who did it, when, for which tenant and which operator. A support action that
  leaves no trace is indistinguishable from an unauthorised one afterwards.
- **It respects the seat limit**, or states plainly that it is overriding it and why. Restoring access
  by silently exceeding what a tenant pays for is a different decision and should not be made by
  accident.
- **The runbook says how**, so the procedure survives the console being unavailable — the same
  reasoning `module-grant-and-revoke.md` already carries.

## What this is not

- **Not a general "act as a tenant" capability.** The platform owner is restoring access, not using it.
  Anything wider is a much larger decision about impersonation with its own personal-data weight, and
  this item must not become the place where that arrives by implication.
- **Not a way around `23-67`.** If both exist, the ordinary answer stays "the tenant cannot lock
  themselves out"; this is for the case where they did anyway.

## Where this is likely to go wrong

- **Restoring a seat is not restoring a role.** The incident that produced this item left the roles
  intact and removed the seat, so restoring the seat was enough. A tenant who stripped their own last
  role needs something else, and an item that only handles seats will look complete and not be.
- **The person asking may not be the tenant.** Whoever can trigger this can hand somebody access to a
  shop's conversations. It is gated on the platform-owner realm role, which nothing in this codebase
  grants — say so in the item that ships it, and record every use.

## Done when

- [ ] A platform owner can restore a locked-out operator's ability to sign in, from the console.
- [ ] The action is recorded and readable afterwards.
- [ ] The seat-limit interaction is decided in the change rather than discovered.
- [ ] The runbook carries the procedure for when the console is not available.
- [ ] The role case is either handled or explicitly named as not handled.
