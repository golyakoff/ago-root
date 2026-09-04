# the calendar reads the account's rung and applies it to its own customers

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-11` — the setting and the event this projects. Cannot start before that
  contract exists.
- **Decision**: `docs/design/decisions.md` §5, including the 2026-09-04 amendment

## Goal

A tenant on the middle rung gets it in the calendar too: a customer's phone number is masked in every
read that carries one, an operator reveals one when they need it, and the reveal is recorded against
their name. A tenant on rung one keeps today's behaviour with no friction at all — which is the
one-chair-salon case, where the person seeing the number **is** the tenant.

## What exists, and what is missing

`20-12` (done 2026-08-31) built the two ends of the ladder without naming it as one.
`Permission.CustomerRead` gates the phone on `GetPendingBookingsForTenantHandler`,
`GetTenantContactsHandler`, `GetWorkerSlotsHandler` and `RecutPreviewHandler`, and the phone is
**absent** from the list read models rather than merely hidden, so an operator's all-day screen never
holds it. `RoleAssignment.GrantsCustomerRead` is already a snapshot taken at grant time.

What is missing is the middle: a state where the number is *reachable* but not *ambient*, and where
reaching it leaves a trace. And, since §5's amendment, the fact that the rung is not the calendar's
to choose.

## Context to read first

- `docs/design/decisions.md` §5 in full, especially the last paragraph on why rung three must not be
  sold yet, and the amendment's audit-view rule
- `docs/backlog/23-11-*.md` — the event, and the reason the setting is not stored here
- `docs/backlog/20-12-*.md`; `docs/design/flows.md` 4.3 and 3.2;
  `docs/design/ui-inventory.md` §7.1, §7.4, §7.5, §7.7
- `Ago.Calendar.Application/Abstractions/IRoleAssignmentProjectionStore.cs` and
  `RoleAssignmentProjectionStore.cs` — the projection shape this copies, including its full-replace
  rule and why that makes the consumer idempotent
- `Ago.Calendar.Domain/Customer.cs` — `PhoneVerifiedAt` and `RecordVerifiedPhone`
- `docs/architecture/tenant-isolation.md`, `docs/architecture/messaging.md`

## Scope

- A **projection of the account's rung**, written by a consumer of `23-11`'s event, in the same shape
  `RoleAssignmentsChangedConsumer` already establishes: the event carries the complete current value,
  the consumer replaces rather than merges, and a redelivery changes nothing.
- **A tenant with no projected value behaves as `Visible`.** State it: the projection can legitimately
  lag or be absent for a tenant older than the event, exactly as `ITenancyReadStore`'s own remarks
  record for a tenancy whose `tenants` row has not appeared yet. Defaulting to *masked* would break
  every existing tenant on the strength of a message that had not arrived.
- On the masked rung, the four `CustomerRead` read paths return the phone masked **in the read
  model**, so the unmasked value never reaches the browser as part of a list.
- A reveal: one customer, one reveal, gated on `Permission.CustomerRead` exactly as the list is,
  tenant-scoped like every sibling read. It returns the number and writes a record.
- A **reveal record** — tenant, customer, operator, when, which surface asked — with its own
  retention and its own prune, and a tenant-facing read of it.
- **"Verified by operator" is a different fact from "verified by code", and is recorded separately.**
  `Customer.PhoneVerifiedAt`/`RecordVerifiedPhone` holds the code's answer today. §5 asks for the
  operator's own "I called and it is them" as a distinct mark — and it lives only on rungs one and
  two, because somebody who cannot see a number cannot confirm it by calling. That is a useful test
  of whether the ladder is being described honestly, and it is the denominator the amendment asks
  for: forty revealed and thirty-one confirmed is work; forty revealed and two confirmed is a
  question.
- `ago-console`: `/calendar` queue, `/calendar/contacts`, `/calendar/workers/:id/slots` and the
  re-cut preview reveal on demand rather than rendering a number. The existing "hidden" meta word
  (`ui-inventory.md` §7.1) stays for the caller who lacks the permission entirely — **masked and
  forbidden must not look the same**, which is `flows.md`'s own recurring rule.
- `authorization.md`, `tenant-isolation.md`, `data-model.md` and `personal-data.md` carry the route,
  the tables and the fact that a reveal record is personal data about an operator.

## Out of scope

- Storing the rung as the calendar's own setting, or offering a control for it here. It is the
  account's, and this product reads it. A second writable copy is exactly the disagreement `23-11`
  exists to prevent.
- Rung three, and any interface implying it exists.
- Click-to-call or system-sent messages.
- Putting reveal counts on any screen where operators are compared. §5's amendment: the operator who
  calls customers back reveals forty numbers and the one who does not reveals two, and a manager
  reading that punishes the useful one.
- Changing what `Permission.CustomerRead` means.

## Done when

- [ ] A tenant on `Visible`, and a tenant with no projected value at all, both see today's behaviour
      byte for byte.
- [ ] A tenant on the masked rung gets masked values in all four read paths, and no unmasked value
      appears anywhere in a list response.
- [ ] A reveal returns the number and writes exactly one record naming the operator.
- [ ] A caller without `CustomerRead` cannot reveal, and gets the refusal the list already gives.
- [ ] A caller of another tenant cannot reveal (a tenant-isolation test).
- [ ] An operator-confirmed number is distinguishable from a code-verified one in the read model, and
      the confirm act is refused on a rung where the number cannot be seen.
- [ ] A redelivered rung event leaves one projected value.
- [ ] The tenant can read the reveal record, and the screen states what it is for.

## Open questions

None.
