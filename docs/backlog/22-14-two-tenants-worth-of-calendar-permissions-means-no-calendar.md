# a person with calendar permissions on two tenants gets no calendar at all

- **Stage**: 22
- **Status**: done (2026-09-05), `ago-calendar#41`, `ago-console#103`, `adr/0100`. Deployed
  2026-09-04; the projection backfill that day showed two people holding two tenants each, which
  is this item's own case, live. The product question below was answered on
  2026-09-04: **build the switcher**. The second alternative — one person, one tenant, refuse to
  create the second grant — is not in scope; see Outcome.
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

- [x] A subject with calendar permissions on two tenants either chooses, or is prevented from
      reaching that state at all — chosen deliberately, with the reasoning recorded. **Chooses**;
      `adr/0100`.
- [x] Whichever it is, it is covered by a test, since the shape has none today. `TenantSwitchingTests`
      (real Postgres, real HTTP, real `PermissionChecker`), `CalendarElsewhereNotice.test.tsx`, and two
      new cases in `calendarApi.test.ts`.
- [x] If it stays a refusal, the person is told something, and an operator can find out why from a
      log rather than from reading this file. **It did not stay a refusal**, so this clause is met the
      other way: the only refusal left is naming a tenant you hold nothing in, and the console's
      `/calendar` screen now names the shops where your calendar actually is instead of showing the
      same sentence a never-granted person sees.

## Outcome

**The switcher, and the tenant travels in a request header** (`adr/0100`). Two repositories, one
promise.

`ago-calendar`: `IRoleAssignmentProjectionStore.FindTenantIdAsync` became `ResolveTenantAsync`,
taking the tenant the caller named. Its requested-tenant branch is one query whose `WHERE` carries
both the operator id and the named tenant, so the verification *is* the authorizing read rather than
a check beside it — a tenant this operator holds nothing in returns `null`, never a fallback to one
they do hold. `OperatorIdentityClaimsTransformation` reads the name from `X-Ago-Active-Site`,
`adr/0068`'s existing header, because a calendar `TenantId` and a chat `SiteId` are the same value
(`RoleAssignmentsChangedConsumer`). New: `GET /api/v1/me/tenancies` behind a `calendar-identity`
policy — the enumeration the console cannot offer a choice without. No migration.

`ago-console`: `calendarApi.ts`'s single `send()` chokepoint now carries the header, so the shop
picker `13-07` already shipped steers both products rather than a second switcher being built. The
`/calendar` refusal additionally names the shops that *do* have a calendar for this person, which is
what makes "you have none" and "you have one, elsewhere" distinguishable — the item's own defect.

**A one-tenancy operator is unaffected**: with the header, it resolves to their single tenancy; with
none, the pre-`22-14` single-row branch runs unchanged. No URL, route or screen changed for them.

**What it cost**: an ordinary operator can now name a tenant, which adds `Ago.Calendar.Api` to
`tenant-isolation.md`'s caller-chosen category — previously the platform owner's four handlers alone.
`adr/0100`'s Consequences states that plainly, and `authorization.md` records the three refusals.

## Context

`22-05`/`adr/0093`. Found by reading the projection store, not by anything failing — which is why it
gets its own number rather than a line in that item's Outcome.
