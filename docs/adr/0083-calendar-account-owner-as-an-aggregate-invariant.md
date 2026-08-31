# ADR-0083: Calendar's account owner is an aggregate invariant, not a bypass

- **Status**: Accepted
- **Date**: 2026-08-31
- **Stage**: 20 (extends `20-01`/`20-12`)

## Context

`20-12` needed a way for a tenant's own account owner to always retain visibility into customer contact
data (`Permission.CustomerRead`), even as the same item introduces the ability to grant that permission
to some operators and withhold it from others. Two existing shapes were the obvious places to look for a
precedent, and neither fit:

- **`adr/0032`'s platform-owner concept.** Reading the real code before assuming this was reusable: it
  resolves to AGO's own cross-tenant staff, identified by a Keycloak realm role, entirely outside any
  tenant's own RBAC — a support/operations concept, not a tenant's own admin. Reusing it here would have
  quietly given AGO's own staff read access to every tenant's customer contacts as a side effect of
  fixing a narrower problem.
- **`13-07`'s tenant-local RBAC model.** Deliberately flat — every operator is an ordinary role-holder,
  with no privileged, unremovable role built into the model at all. Correct for its own scope; it simply
  never needed to answer "does one operator ever get treated differently from the others" because
  nothing before `20-12` made that distinction meaningful.

Calendar has no third existing concept to fall back on. `20-12`'s own account-owner idea is new,
narrower than either precedent, and specific to this one guarantee: one operator per tenant — the one
`RegisterTenantHandler`'s own provisioning transaction creates — must never end up holding zero roles
that grant `CustomerRead`.

## Decision

**The guarantee lives in `Operator.Grant`/`Operator.Revoke` themselves, as a Domain invariant the
aggregate refuses to let a caller violate — not as a bypass path that skips the permission system, and
not as a console-level convention a future screen could forget to enforce.**

`Operator.IsAccountOwner` is a `bool`, set once, only by `Operator.Create`, with no later mutator —
matching how `Id`/`TenantId` themselves carry no setter: who provisioned a tenant is a fact about how the
row came to exist, not state a later request can flip. `Grant` refuses to complete a grant that would
leave an account-owner operator holding no `CustomerRead`-granting role at all (a real, if narrow, case:
their only role so far grants nothing, and the role being added doesn't either). `Revoke` refuses to
strip the *last* `CustomerRead`-granting role from an account owner, computed by checking every
*other* currently-held role first — revoking one of several is fine; revoking the only one is refused.
Both throw `AccountOwnerRoleException`, the same "the aggregate's own rule, not a caller's job to
remember" shape `TenantMismatchException` already establishes for the cross-tenant case one line above
each of them.

**Crucially: `PermissionChecker` itself is untouched.** The account owner is never granted `CustomerRead`
through a special-cased check at read time — they hold it because `Grant`/`Revoke` never let them not
hold it. A read of "does this operator have `CustomerRead`" asks the identical question, resolved the
identical way, for every operator including the owner. There is no second code path to keep in sync with
the first, and no way for a future permission-checking call site to forget the exemption exists, because
there is no exemption to forget — only a guarantee about what states `Grant`/`Revoke` can produce.

## Consequences

- **Positive**: the guarantee cannot be silently broken by a future console screen, a bulk-import script,
  or any other caller of `Operator.Grant`/`Revoke` that doesn't know this rule exists — it is enforced at
  the one place every mutation of an operator's roles must pass through, not at each place that happens
  to call it today.
- **Positive**: `adr/0032`'s platform-owner boundary stays exactly as narrow as it already was — this
  decision adds nothing to what AGO's own staff can see across tenants.
- **Negative, named plainly**: a tenant currently has **exactly one** account owner, fixed at
  provisioning time, with no path to transfer the role or add a second one. If a real tenant ever needs
  to hand ownership to a different operator (the original owner leaves the business), no mechanism
  exists for that today — a real, likely near-term gap, not addressed by this decision.
- **Negative**: `Operator.Revoke`'s own guard requires loading every one of an operator's current role
  assignments to evaluate ("does any *other* held role also grant `CustomerRead`") — cheap at today's
  scale (an operator holds at most a handful of roles), but worth remembering if a future tenant ever
  holds dozens.

## Alternatives considered

- **A platform-owner-style bypass in `PermissionChecker`** (`if (operator.IsAccountOwner) return true;`
  for `CustomerRead` specifically). Rejected: this is exactly the shape that makes the account owner's
  access invisible to `PermissionChecker`'s own callers — nothing in the read path would show that this
  operator's access comes from a special case rather than a real granted role, and a future permission
  audit would have to know to check two places.
- **A console-level convention** ("the UI simply never offers to revoke the owner's last qualifying
  role"). Rejected outright: exactly the "trust every future caller to remember" shape this codebase's
  own conventions already reject for cross-tenant checks (`TenantMismatchException`'s own precedent) —
  a direct API caller, a script, or a future screen nobody reviewed against this rule would silently
  succeed in breaking the guarantee.
- **Reusing `13-07`'s flat model with no owner concept at all**, and instead simply never building a
  narrower role that excludes `CustomerRead` (every operator keeps every permission, permanently).
  Rejected: this is the status quo `20-12` exists to move past — the account owner's request was
  specifically for a *narrower* role to exist, which requires an owner concept to keep at least one
  operator whole.
