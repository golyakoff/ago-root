# a locked-out tenant can be let back in without a database

- **Stage**: 23
- **Status**: done
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

- [x] `/owner`'s tenant detail screen (`23-65`) gets an Operators section with a per-row Restore
      seat action, calling `POST /api/v1/owner/sites/{siteId}/operators/{operatorId}/restore-seat`
      (`ago-chat#240`, `ago-console#174`) - gated on the existing platform-owner realm role, same as
      every other owner surface.
- [x] Every restore writes an `AccessRecord` (who, when, tenant, operator) - the same audit
      mechanism every other owner action already uses (`24-12`), proven by
      `OwnerOperatorsEndpointsTests`.
- [x] Decided: mirrors `adr/0118`'s revoke-override asymmetry. Within the paid seat limit,
      restoring needs no ceremony; past it, refused (`409`) unless `force: true` with a non-blank
      `reason`, recorded verbatim in a new `operator_seat_restore_overrides` table - an unconditional
      refusal would defeat this item's own purpose (the tenant's own remedy is unreachable while
      locked out), a silent override would violate "states plainly that it is overriding it and why."
- [x] `docs/runbooks/seat-restore.md`, mirroring `module-grant-and-revoke.md`'s structure -
      including a body-less `curl` for the ordinary case.
- [x] Explicitly not handled, stated in three places (handler doc comment, the console's own
      empty-role warning on the operators table, and the runbook): restoring a seat makes
      `Operator.CanSignIn` true regardless of role, but grants no role back. An operator who
      stripped their own last role can sign back in with no permission once inside - matches the
      shape of the real 2026-09-07 incident this item was filed from (role intact, only the seat
      released).
