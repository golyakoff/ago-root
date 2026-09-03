# a person with calendar permissions on two tenants gets no calendar at all

- **Stage**: 22
- **Status**: ready
- **Found**: 2026-09-03, reading `22-05` before merging it.

## The gap

`RoleAssignmentProjectionStore.FindTenantIdAsync` answers "which tenant is this subject acting in"
and refuses on **both** zero matches and more than one:

```csharp
return tenantIds.Count == 1 ? tenantIds[0] : null;
```

Refusing rather than guessing is right — there is no honest answer to "which of these two" without
asking. But the consequence is that a person holding calendar permissions on two tenants resolves to
no tenant, so `OperatorIdentityClaimsTransformation` produces a principal the `calendar-operator`
policy rejects, and every calendar screen is simply absent for them.

**Absent, not broken, is the console's own designed behaviour for "no permissions" (`19-03`), so this
failure is indistinguishable from never having been granted anything.**

## Why it is newly reachable

Under the model `22-05` deleted, this was impossible: one `operators` row per subject, with a single
`tenant_id`, and a unique index enforcing it. The projection is keyed `(operator_id, tenant_id)`, so
two rows for one subject is now an ordinary, representable state — and it is the state any person who
works for two shops lands in the moment both enable the calendar.

`22-05`'s own author flagged the shape as designed-but-untested. This item is the part that is not
merely untested: the behaviour itself is wrong for a real person.

## What it must produce

The question this has to answer is **whose choice the tenant is**, and it is a product question, not
a lookup:

- If a person can act in several tenants, the console has to let them pick, and the picked tenant has
  to travel with the request rather than be inferred from identity. That is a real surface, not a
  fallback.
- If the answer is "one person, one tenant, by policy", then two rows is a state the system should
  refuse to *create*, loudly, at the moment of granting — not one it silently resolves to nothing at
  sign-in.

Either answer is defensible. Silently resolving to nothing is not, because nothing anywhere says why.

## Done when

- [ ] A subject with calendar permissions on two tenants either chooses, or is prevented from
      reaching that state at all — chosen deliberately, with the reasoning recorded.
- [ ] Whichever it is, it is covered by a test, since the shape has none today.
- [ ] If it stays a refusal, the person is told something, and an operator can find out why from a
      log rather than from reading this file.

## Context

`22-05`/`adr/0093`. Found by reading the projection store, not by anything failing — which is why it
gets its own number rather than a line in that item's Outcome.
