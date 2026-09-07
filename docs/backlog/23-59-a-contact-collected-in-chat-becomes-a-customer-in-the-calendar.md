# a contact collected in chat becomes a customer in the calendar

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-58` (the contact is collected), `22-07` (the module grant). `adr/0147` is the
  decision.
- **Decision**: `adr/0147`, from the author's answers of 2026-09-07.

## Goal

A tenant who collects a phone number in chat and later takes a booking is dealing with **one person**,
and does not have to type them in twice.

## Scope

- **Chat publishes, through the outbox, in the same transaction as the contact write.** It does not
  know or care whether a calendar exists.
- **The calendar consumes and creates a customer**, idempotently, for tenants where the module is
  granted.
- **Granting the module carries over every contact ever collected for that tenant**, not only later
  ones. A replayable pass, not a side effect of the grant: a grant that succeeds and a carry-over that
  fails must be two facts, so the second can be re-run without redoing the first.
- **A phone matching an existing customer creates a separate row**, marked as having come from chat.
  Merging is `23-60` and is somebody's deliberate act.

## Where this is likely to go wrong

- **The backfill is unbounded.** A tenant with years of chat history grants the calendar and the pass
  is large. Nothing user-facing may wait on it, and it must be interruptible and resumable rather than
  all-or-nothing.
- **Two products, two databases** (`adr/0093`). Neither may read the other's tables, and the temptation
  to "just query chat" will be strongest exactly here.
- **Erasure now has two homes.** Deleting a contact in chat does not delete the customer in the
  calendar. This item does not solve that and must not pretend to — it is named in `adr/0147`'s
  consequences and belongs with `24-09`.

## The question this item does not answer

**Whether `24-05`'s consent wording permits it.** A visitor gave a phone number to a chat widget;
carrying it into a booking system, retroactively, is a use that wording has to actually cover. If it
does not, the wording changes rather than this design. That goes to whoever reviews `23-52`'s documents
and is not an engineering decision.

## Done when

- [ ] A contact recorded in chat appears as a customer in the calendar, for a tenant that has it.
- [ ] The same contact arriving twice produces one customer.
- [ ] Granting the module carries over contacts collected before the grant, shown working on a tenant
      with pre-existing contacts.
- [ ] A failed carry-over can be re-run without re-granting anything.
- [ ] Neither product queries the other's schema, asserted by a test rather than by inspection.
