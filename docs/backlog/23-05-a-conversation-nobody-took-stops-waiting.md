# a conversation nobody took stops waiting, and the site chooses how long that takes

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-03` (the interval store and its `source` column) and `23-04` (the compare-free
  increment on `IOperatorCapacity`, which this path reuses rather than re-inventing). `23-20` is not
  a dependency but must land compatibly: an `Away` operator is not `Online` and must not receive one
  of these either.
- **Decision**: `docs/design/decisions.md` §2, bullets 3 to 6

## Goal

A conversation nobody has taken stops waiting. After a per-site penalty period — two minutes by
default — the assignment engine assigns it to the least-active **online** operator with the capacity
predicate dropped, and records that this is how it came about.

§2's reason, which belongs in the item rather than in someone's head: **a waiting customer is worse
than uneven load.**

## Why the period is per site and not a constant

A one-chair salon and a five-operator service have different tolerances. A constant would choose for
them. Two minutes is the default, not the rule.

## What this is called

Not "forced". `23-03`'s naming note: the stored provenance is `Additional`, and what a reader sees is
a **standard** conversation or an **additional** one. §2's second amendment is explicit that "forced"
is a bad label for a screen a person is judged on, and this is the path that would have carried it.

## Context to read first

- `docs/design/decisions.md` §2, bullets 3 to 6, including the case it explicitly excludes, and the
  naming amendment
- `docs/design/flows.md` 2.1 and 1.2; `docs/design/ui-inventory.md` §3.1 — the rail's `Waiting 4m`
  elapsed label, which is the operator-facing half of this and **already exists**
- `docs/architecture/concurrency.md`; `Ago.Chat.Worker/SkipLockedAssignmentClaimer.cs` and
  `RedisLockAssignmentClaimer.cs`, whose contract (`IAssignmentClaimer`) is that they behave alike
- `docs/backlog/14-04-offline-auto-reply.md` and `adr/0066` — the nobody-is-online case, which this
  rule deliberately does not touch
- `docs/architecture/caching.md` and `CLAUDE.md` rule 8

## Scope

- `sites.assignment_penalty_seconds`, default `120`: one additive column on the `Site` aggregate,
  written through the existing site-configuration path and invalidated through `SiteSettingsChanged`
  / `SiteCacheInvalidationConsumer` like every other site setting. **The claimer reads it inside its
  own transaction, never from the cache** — it is configuration a write decision depends on
  (`CLAUDE.md` rule 8).
- `SkipLockedAssignmentClaimer`'s candidate selection gains a second pass, used only for a
  conversation whose age exceeds that site's penalty: the least-`active_chats` `Online` operator with
  the capacity predicate dropped, claimed through `23-04`'s compare-free increment rather than
  `TryClaimAsync`, which would refuse. `RedisLockAssignmentClaimer` gets the same treatment — the two
  implementations must not diverge, which is `IAssignmentClaimer`'s own contract.
- The conversation's age comes from `Conversation.CreatedAt` against `IClock`, never from the database
  clock (`CLAUDE.md` rule 11).
- `source = Additional` on the interval `23-03` opens for these rows.
- **If no operator is `Online` at all, nothing is assigned.** There is nobody to assign it to; that
  case is `14-04`'s offline auto-reply and is unchanged. Assert it, because the tempting bug here is
  waking an `Offline` operator's row.
- A site-configuration control for the period, on the settings screen that already owns site
  behaviour — `/settings/auto-reply` is the nearest neighbour by subject.

## Out of scope

- Notifying the operator differently. The rail already announces a new assignment ("A new
  conversation was assigned to you."); whether this one should read differently is a design answer.
- Any per-operator fairness rule beyond least-active-first. §2 accepts uneven load as the price.
- Making the period depend on anything but the site.
- Showing the waiting conversation's age. `ui-inventory.md` §3.1 records that the rail already renders
  `Waiting 4m`, ticking every 10s — §2's "a waiting conversation shows its age" is already true.

## Done when

- [ ] With every operator at capacity and one conversation waiting past the site's period, it is
      assigned to the least-active online operator and `active_chats` exceeds `capacity`.
- [ ] Before the period elapses, that same conversation is not assigned — the existing behaviour,
      asserted so the change is bounded.
- [ ] With no operator `Online`, nothing is assigned regardless of age, and `14-04`'s auto-reply path
      is unaffected.
- [ ] An `Away` operator is never selected by this pass.
- [ ] The period is read per site: two sites with different values behave differently in one test.
- [ ] Two `Worker` replicas racing produce exactly one assignment and one interval.
- [ ] Every interval opened by this path carries `Additional`.
- [ ] `concurrency.md` states the rule and its exception; `data-model.md` carries the new column;
      `caching.md` states that this setting is read inside the transaction and never from the cache.

## Open questions

None.
