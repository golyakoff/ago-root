# One account id — the calendar's tenancy equals it, rather than being replaced by it

- **Stage**: 22
- **Status**: ready
- **Depends on**: `22-01`

## What changes

AGO Calendar stops minting its own tenancy. Its tenant id becomes the account id — the same value
`ago-chat` already calls `SiteId` and `ago-faq` already uses directly as its own scope key (`19-03`).

**The wording carries the whole decision.** *Equals*, not *replaced by*:

- The calendar **keeps its `tenants` table.** Nine tables hold a foreign key to it, and the granted
  worker quota (`22-07`) has to be readable inside a calendar transaction, which rule 8 requires. The
  table was never optional.
- The calendar **keeps `RegisterTenantHandler` and `20-27`'s provisioner.** The account side supplies
  the id when it provisions; nothing forbids another caller supplying one. This is what keeps a
  calendar-only customer possible without making it a feature today — see Out of scope.

Deleting the table and the minting path would save one table with zero rows, and would weld shut the
only door worth keeping open. So it is explicitly not done.

## Why it is cheap

`TenantId` is `readonly record struct TenantId(Guid)`. It appears in 123 of `ago-calendar`'s 313
source files, and **none of them change** — a strongly-typed wrapper does not care where its value
came from. What changes is provenance, in one place.

The database is empty: eleven migrations, zero rows. There is no data migration and no customer to
disturb, and that is true only until the first tenant exists.

## Done when

- [ ] A calendar tenant's id is the account id, end to end, proven by provisioning one and reading
      both rows.
- [ ] `RegisterTenantHandler` and the `20-27` provisioner still work for a standalone tenant — proven,
      because this is the door `22-01` decided to keep.
- [ ] Nothing in the calendar mints a tenancy identifier of its own any more.

## Out of scope

- **Selling the calendar without the chat.** The door stays open here; the product does not exist
  until somebody wants it, and the expensive half of it is not tenancy but exposure — the embeddable
  booking widget, closed by `PublicBookingApiGate` (`adr/0090`). Its own item, its own ADR revisit.
