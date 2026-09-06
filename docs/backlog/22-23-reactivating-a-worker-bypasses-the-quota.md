# reactivating a worker bypasses the quota that deactivated it

- **Stage**: 22
- **Status**: done (2026-09-06). One port method beside the one creation already uses, and a
  transition check the item did not ask for and needed.
- **Depends on**: `22-07` (the quota this walks around), which must land first
- **Decision**: none needed — `22-07`'s own `adr/0125` already decided the shape this must follow

## Goal

A tenant cannot end up with more active workers than they have paid for, by any path.

## What is actually true today, verified 2026-09-06 by reading the handler

`22-07` enforces the quota in exactly one place: `WorkerRepository.TryAddWithinQuotaAsync`, taking a
`FOR UPDATE` lock on the tenant row and counting active workers before allowing a **create**.

`UpdateWorkerHandler` — `PUT /workers/{id}` — is a different path, and it is not gated:

```csharp
if (command.IsActive)
{
    worker.Reactivate(now);
}
```

No quota read, no lock, no count. So the sequence that defeats the whole item is short: a tenant on a
quota of five has ten workers, downgrades to three, `22-07` deactivates the seven most recently
created — and the tenant reactivates them one at a time through the ordinary edit screen.

This was **found and reported by the worker that built `22-07`**, which deliberately did not fold the
fix in. That was the right call: closing it needs a new repository method, a restructured handler and
its own concurrency tests, and `22-07` was already one promise (`CLAUDE.md` rule 15).

## Why this is a gap rather than an oversight

`22-07` was scoped from the question "what happens when a tenant buys or downgrades an add-on", and it
answered that completely. Reactivation is a pre-existing endpoint that predates the concept of a quota
entirely — there was nothing to check when it was written.

It matters more than an ordinary hole because the whole *point* of the deactivate-the-excess design is
that a downgrade never destroys anything: the workers stay, deactivated, so a tenant who upgrades again
gets them back. That kindness is exactly what makes the bypass trivial — the rows are sitting there,
one edit away.

## Scope

- Reactivation is refused when it would put the active count above the quota, under the **same lock**
  `TryAddWithinQuotaAsync` takes on the tenant row — not a second, differently-shaped check.
- The refusal is a distinguishable error, so the console can say "you are at your limit" rather than a
  generic failure.
- A concurrency test at the same degrees `22-07`'s own uses: many concurrent reactivations against a
  quota with one free slot produce exactly one reactivated worker.

## Out of scope

- Any change to how the quota is granted or how a downgrade chooses its excess. `22-07`/`adr/0125`
  settled both.
- The console screen. This item makes the API refuse; whether the button is disabled ahead of time is
  a separate, frontend-shaped question.

## Done when

- [x] Reactivating a worker past the quota is refused, with nothing written.
- [x] The refusal is proven under real concurrency, not only sequentially.
- [x] The check shares `TryAddWithinQuotaAsync`'s lock discipline rather than introducing a second
      shape for the same invariant.

## Outcome

`ago-calendar#45`, merged 2026-09-06.

**The gate reuses creation's shape rather than adding a second one** - the same
`SELECT worker_quota ... FOR UPDATE` plus a real `COUNT(*)`, inside the transaction that decides.
Two reasons, and only one is style: a second way of counting the same invariant is how the two drift,
and rule 8 forbids a write decision reading anything but the database inside its own transaction.

**What the item did not specify turned out to be the interesting half.** Only a *false-to-true
transition* counts as a reactivation. The console's edit form resends the worker's current activity
alongside whatever the human actually changed, so gating on the requested end state alone would have
refused an ordinary rename the instant a tenant sat exactly at its quota. A test asserts the rename
stays legal at the limit, and it reddens if the transition guard is dropped.

That is worth keeping because it is the shape of a whole class of quota bug: **the check has to ask
what changed, not what was asked for.**

**One pre-existing test needed a quota to keep meaning what it meant.** `WorkerEndpointTests`
deactivates and reactivates the seeded worker to prove the display-name freeze, and the seed's default
quota of zero made that reactivation illegal under the new gate. Seeded with one - the scenario the
test was always about - rather than exempting the path, which would have removed the coverage instead
of fixing the fixture.

**Verified independently before landing**: two consecutive full-solution runs green (205 / 160 / 26 /
26 / 269), and the fails-before re-proven here rather than taken from the report. One unrelated test
(`ConfirmationSweepTests`) failed once on a first run and passed in four consecutive runs afterwards -
recorded rather than filed, because one unreproduced observation is not yet a flake.