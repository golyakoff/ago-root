# Tenant lifecycle across two databases

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-03`, `22-07`
- **Found**: 2026-09-03, and it was missing from this stage's first draft. Recorded because the
  omission is the informative part: suspend/delete/export is the workstream nobody writes down until
  something has already gone wrong.

## Why it exists at all

Once a customer has rows in two databases, three operations stop being one product's business. **None
of this is caused by the calendar keeping its own tenancy row** — it is bought by the two products
having two schemas, which `22-01` deliberately keeps. It would appear in every shape considered,
including hoisting tenancy into the platform, because a customer's conversations and their bookings
are in different places either way.

## The three, and what each needs

**Suspension.** Rule 8 forbids the calendar asking chat at booking time whether the account is still
paid up, so the calendar holds its own `active` flag kept fresh by propagation. A late message means a
suspended customer keeps taking bookings — so the staleness bound is a number this item has to state,
not a hope.

**Deletion and erasure.** `personal-data.md` and `16-03` require a tenant's data to be removable, and
`ago-chat` already has `SiteErasureJob` and `ConversationErasureJob` for its half. The calendar has
no equivalent. Over at-least-once delivery the system must be able to **prove the second half
completed** rather than merely having sent it — this is the clause that makes this an obligation
rather than tidiness.

**Export.** `SiteExportJob` exists on the chat side; a tenant's export now has to gather from both,
and say so when one half is missing rather than producing a quietly partial archive.

## And the fourth thing, which is smaller but sharper

**Reconciliation.** Nobody writes it until it is needed: *every account with the add-on has exactly
one calendar tenant, and no calendar tenant exists without an account.* Half-failed provisioning
(`22-07`) and half-failed deletion both show up here first, and neither shows up anywhere else.

## Done when

- [ ] Suspending an account stops the calendar accepting bookings, within a stated bound, proven by
      doing it.
- [ ] Erasing a tenant removes both halves, and the completion of the second half is observable.
      Proven by erasing one and looking, not by reading the job.
- [ ] An export contains both halves, or fails loudly.
- [ ] A reconciliation check exists and is run somewhere it will be seen.
