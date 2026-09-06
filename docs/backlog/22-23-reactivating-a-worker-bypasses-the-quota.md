# reactivating a worker bypasses the quota that deactivated it

- **Stage**: 22
- **Status**: ready
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

- [ ] Reactivating a worker past the quota is refused, with nothing written.
- [ ] The refusal is proven under real concurrency, not only sequentially.
- [ ] The check shares `TryAddWithinQuotaAsync`'s lock discipline rather than introducing a second
      shape for the same invariant.
