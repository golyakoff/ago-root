# 25-70 · A suspended tenant's own console says nothing about it

- **Stage**: 25
- **Status**: ready
- **Depends on**: `22-08` (done, `ago-chat#271`/`ago-calendar#62`/`ago-console#214`) - the mechanism
  this item's own missing half sits on top of.
- **Found**: 2026-09-13, landing `22-08`. That item's own Scope prose names this explicitly - *"What
  the tenant sees. The console says the account is suspended, since when, until when, and what to do
  about it. That is the entire visible effect, and it is deliberately the only one."* - but no Done-when
  box named it, and the implementing worker built only the platform-owner-facing screens (suspend an
  account, list, extend, unblock). A real, described piece of scope shipped as unbuilt rather than
  silently dropped or silently added.

## What is actually true today

A suspended account's own operators can still sign into their console - nothing about `22-08` blocks
that - and see nothing telling them why the calendar stopped taking bookings or why sending stopped
working. They would discover the effect (a refused booking, a refused send) with no stated cause.

## Scope

- The tenant's own console reads its own account's suspension state (`GET` whatever endpoint already
  backs the owner's list, scoped to the caller's own site rather than every site) and shows: suspended,
  since when, until when, and a short line on what to do (contact support, or whatever the actual
  process is - a real question this item should answer, not invent silently).
- This is read-only for the tenant - they cannot lift or extend their own suspension, only see it.

## Out of scope

- Anything that lets a tenant act on their own suspension. `22-08`'s own design keeps that the
  platform owner's act alone, and this item does not reopen it.

## Done when

- [ ] An operator signed into a suspended tenant's own console sees the suspension, since when, until
      when, and what to do about it - proven by suspending a real account and loading its console.
