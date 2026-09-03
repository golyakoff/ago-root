# Give AGO Calendar a way to get its first tenant

- **Stage**: 20
- **Status**: done (2026-09-03) — the mechanism exists and is merged. **No tenant has been created
  yet**, and the owner's first sign-in — the whole point — is still owed.
- **Found**: 2026-09-03, while writing a walkthrough of the calendar console. The walkthrough could
  not get past the first screen.

## The gap

`ago_calendar` on the live node held **eleven migrations and zero rows**. No tenant, no operator, no
role.

The only code creating a `Tenant` was `RegisterTenantHandler`, with exactly one caller:
`DevProvisioningEndpoints`, which maps only outside Production. That gate is correct and was made
explicit days earlier (`8-11`) — nobody should provision a tenant by POSTing to an unauthenticated
endpoint on a live host.

Every other write lives under `/api/v1/console`, guarded by `RequireAuthorization`. Reaching it needs
an `Operator`; an `Operator` comes from `RegisterTenantHandler`'s own transaction or from
`InviteOperatorHandler`, which is itself inside the guarded group.

**So the first tenant could not be created by anyone, through any path.** Authentication succeeded and
landed on an account that did not exist — which also explains, after the fact, why nobody had signed
in to the console yet and why that would have looked like a broken console rather than a missing
account.

## What was built, and what it replaced

`RegisterTenantHandler` now accepts an **owner email** in place of a Keycloak subject, creating the
account owner invited-and-unlinked exactly the way `InviteOperatorHandler` already creates a
colleague. `adr/0088`'s claims transformation links it on the owner's first sign-in, by email — an
existing mechanism reused, not a new one.

Exactly one of `ExternalSubjectId` or `OwnerEmail` is required, refused before either branch runs.
`Operator.Create` accepts both or neither by design, so the guard has to live in the handler or a
caller passing both silently gets whichever branch is checked first.

`Ago.Calendar.Provisioner` runs it: a headless host — `Microsoft.NET.Sdk`, no generic host, no DI
container, no route, no port. `Ago.Calendar.Migrator`'s shape, for its reason: a container adds a
startup surface to a process whose whole value is that it does one thing and stops. It has
**deliberately no input for a Keycloak subject at all**, so one cannot be invented.

**The `ago-demo-provisioner` shape (`adr/0058`) was considered and rejected on the code.** That client
exists to call Keycloak's Admin API and create a Keycloak *user*, because a demo viewer has no
account. A real tenant's owner registers their own, so nothing here needs to create identities — and
`adr/0058` itself names holding an admin credential as a new class of secret this project has avoided.
It would also have meant generalising from zero callers.

## Done when

- [x] A path exists that can create a tenant in Production without weakening the `/dev/*` gate. —
      `Ago.Calendar.Api/Program.cs` is not in the diff and `DevEndpointsEnvironmentGateTests` passes
      unmodified, which is the control.
- [x] Nothing anonymous can reach it. — the project is not a web SDK project and contains zero
      occurrences of `WebApplication`, `MapGet`, `MapPost`, `Kestrel` or `UseUrls`. Reaching it means
      running a container inside the cluster with the real connection string — the trust boundary
      `Ago.Calendar.Migrator` already occupies, and that one alters schema.
- [ ] **A tenant exists in `ago_calendar` on the live node.** Not yet: it needs the shop's real name
      and the owner's real email, which are inputs a session cannot invent.
- [ ] **Its owner signs in and reaches a screen with their own data on it.** This is the one that
      matters. Every layer beneath it has been proven individually, and today has repeatedly shown
      that is not the same thing.

## Out of scope

- **Self-service signup**, which is the path a real tenant eventually takes and a much larger item.
  This is deliberately the one-shot admin path, chosen because the launch needs one tenant soon and
  signup should not be rushed into existence under that pressure.
