# a contact collected in chat becomes a customer in the calendar

- **Stage**: 23
- **Status**: done
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

- [x] `ago-chat#238`: `RecordVisitorContactDetailHandler` enqueues `ContactCollected` through the
      outbox, in the same transaction as the write, from both entry points. `ago-calendar#51`:
      `ContactCollectedConsumer` upserts into `Customer` (`Source = Chat`) when the tenant has been
      granted the module - checked locally, no cross-database read.
- [x] The upsert conflict target is `(tenant_id, source_contact_id)`, a partial index scoped to
      chat-sourced rows. Independently re-proved: pointing it at the Booking-only index instead
      produces a real Postgres 23505 duplicate-key error.
- [x] `EnableModuleForSiteAsOwnerHandler` stages a carry-over request on every grant;
      `ContactCarryoverBackfill` drains it in batches through a persisted cursor, run automatically by
      `ContactCarryoverJob`.
      with pre-existing contacts.
- [x] The cursor is the request's own row, not tied to the grant. Independently re-proved: suppressing
      cursor advancement fails `AnInterruptedCarryover_ResumesFromItsOwnCursor_WithNoSecondRequest`
      (2 successes instead of 1 - a second request would have been needed); restoring returns it to
      green.
- [x] `ContactCollectedCustomerStoreTests`, the mirror of `RoleAssignmentProjectionDemonstrationTests`'s
      own check: this schema holds no connection string or credential for the other database, so there
      is nothing here for a cross-product read to reach even if a future change tried.
