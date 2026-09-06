# the calendar reads the account's rung and applies it to its own customers

- **Stage**: 23
- **Status**: done (2026-09-06)
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

- [x] A tenant on `Visible`, and a tenant with no projected value at all, both see today's behaviour
      byte for byte.
- [x] A tenant on the masked rung gets masked values in all four read paths, and no unmasked value
      appears anywhere in a list response.
- [x] A reveal returns the number and writes exactly one record naming the operator.
- [x] A caller without `CustomerRead` cannot reveal, and gets the refusal the list already gives.
- [x] A caller of another tenant cannot reveal (a tenant-isolation test).
- [x] An operator-confirmed number is distinguishable from a code-verified one in the read model, and
      the confirm act is refused on a rung where the number cannot be seen.
- [x] A redelivered rung event leaves one projected value.
- [x] The tenant can read the reveal record, and the screen states what it is for.

## Open questions

None.

## Outcome (2026-09-06)

`adr/0123` carries the three decisions this side needed. They were drafted as a separate `0126` and
**folded into `0123` at the author's call (2026-09-06)**: the ladder is one decision about one account
setting, and a reader who opened either half would have seen half of it.

**`20-12` had already built both ends of a ladder without naming it**, which changed the shape of the
work: `Permission.CustomerRead` already gated the phone in four read paths, and the phone was *absent*
from the list read models rather than merely hidden. What did not exist was any rung concept at all.
Worth recording because the migration named `Stage20AddAccountOwnerAndContactVisibility` **is
misleadingly named** — its content is `operators.is_account_owner` and
`operator_roles.grants_customer_read`, `20-12`'s two-layer gate, not a rung. A reader going by the name
would conclude this item was already done.

**Three decisions the item left to whoever built it.**

1. **The calendar gets its own `contact_phone_reveals` table.** `adr/0123` answered "widen the enum or
   build a table" for chat; here the question collapses, because this product has no `access_records`
   to widen in the first place.
2. **Confirmation is gated on `CustomerRead` alone, not on the rung.** §5 reads as a per-rung refusal,
   but rung three is absent from this product's enum too, so there is no rung on which a `CustomerRead`
   holder cannot already see the number — a rung-keyed check would discriminate on nothing.
3. **The consumer commits in one save**, following `RoleAssignmentsChangedConsumer` rather than
   `22-07`'s two-save shape: a rung has nothing to decide from its own prior value, so there is no
   read-decide-write to hold a lock across.

**A negative finding the worker reported rather than hid, and it is the useful part of this report.**
The test named `TheSameRungEventDeliveredTwice_ProjectsOnceAndRecordsTheInboxOnce` **does not
discriminate** a correct `StageAsync` from a naive always-insert one. `EfInboxChecker` catches *any*
unique-violation, not only a duplicate `message_id`, so a spurious primary-key conflict from the
broken version is swallowed and reported as "not new" — rolling back both writes and leaving the same
observable state the correct code produces. `RestagingADifferentRung_ReplacesTheProjectedValue` is the
test that actually proves it. The first test is weaker evidence than its name implies and is **left
that way, said out loud**, rather than renamed to look better.

**The console half is not built and is now `23-30`.** Four screens would have to reveal on demand
instead of rendering a number: the calendar queue, the contacts report, a worker's slots, and the recut
preview. The backend gives them everything they need — a `Masked` flag on every response row, both
verification timestamps on the contacts report, and three new endpoints — so the split is clean and
each half closes green on its own.
