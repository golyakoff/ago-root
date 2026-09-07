# a grant lands eventually and nothing says how long

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-66`, which built the grant whose bound is unstated.
- **Found**: 2026-09-07, carried out of `23-66` at landing.

## Why this is its own number

`23-66`'s fourth Done-when — *the projection bound is stated, and the wait is bounded rather than
hoped for* — is not the same promise as *a quota can be granted at all*, which is what that item
delivered and closed on.

## What is actually true today

A platform owner grants a quantity in `ago-chat`. It reaches `ago_calendar` **through the outbox**,
projected by the consumer that owns `GrantWorkerQuota`. That is the correct shape — rule 4, and
`adr/0093`'s boundary — and `23-66` proved the wire works with a real broker, a real publisher and the
real consumer.

**What is not stated anywhere is how long it takes.** The console screen writes the grant and returns.
Nothing tells the owner the tenant does not have it yet, nothing polls, and nothing says what to do if
it has not arrived. So the honest description of the screen today is *the grant has been recorded and
will apply at some point*, and no part of the product says that out loud.

The failure this produces is specific and cheap to imagine: an owner grants a quota during a support
call, the tenant refreshes, nothing has changed, and the owner grants it again.

## Scope

- **State the bound.** What is the expected and the worst-case delay between the write in `ago-chat`
  and the row in `ago_calendar` — from the outbox dispatch interval and the consumer's own behaviour,
  not from a guess.
- **Say it where the grant is made.** The owner should not have to know what an outbox is to understand
  that this is not instant.
- **Make a repeated grant safe**, or make it visibly unnecessary. At-least-once delivery is assumed
  everywhere (rule 5); a second identical grant must not double anything.

## Out of scope

- Turning the projection synchronous. `22-11`'s own reasoning explains why registration is an RPC and a
  grant is not, and reversing that is a decision, not a fix.

## Done when

- [ ] The delay's expected and worst case are stated, derived from the dispatch interval rather than assumed.
- [ ] Somebody making a grant is told it is not instant, without needing to know why.
- [ ] Granting the same quantity twice is shown to be safe.
