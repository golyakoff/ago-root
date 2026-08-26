# The migrator waits for its database instead of losing a race to it

- **Stage**: 8
- **Status**: ready
- **Depends on**: `8-08` — merged and deployed, and this is a gap that deploying it revealed.

## Goal

A deploy in which Postgres restarts alongside everything else does not need a human to notice the
migrator failed and re-run it by hand.

## How this was found

The first deploy carrying `8-08` and `8-09`, 2026-08-26. `kubectl apply -k overlays/demo` rolled a
dozen workloads at once — the node's checkout had been many commits behind, so `17-05`, `16-05` and
`8-08` all arrived together — and the migrator Job started while Postgres was still restarting:

```
MIGRATION FAILED: NpgsqlException: Failed to connect to <cluster-ip>:5432
  caused by SocketException: Connection refused
```

`backoffLimit: 0` (deliberate — `8-08` argues a failed migration should stop the deploy and be looked
at, not be retried into a crash loop) means the Job stayed `Failed`. The three hosts then did exactly
what they were built to do and refused to start against a schema older than their own build, so the
deployment sat correct-but-down until the Job was deleted and re-applied by hand.

**Nothing here misbehaved.** The guard worked, the failure was loud, and the outcome was safe. What
is missing is that the safe outcome required a person.

## The distinction this item turns on

`8-08` was right that a *migration* failure must not be retried. This is not a migration failure —
**the migration never started.** Those are different events and the current design cannot tell them
apart, because both leave the Job `Failed` with `backoffLimit: 0`.

So the fix is **not** to raise `backoffLimit`, which would also retry a genuinely broken migration and
undo the reasoning `8-08` recorded. It is to make "the database is not there yet" not be a failure at
all.

## Scope

- **The migrator waits for its database to accept connections before it begins**, with a bounded
  timeout, and treats not-yet-listening as a normal state to wait through rather than an error to
  exit on. The shape already exists in this codebase: `8-08`'s own `SchemaVersionGuard` waits 60s for
  the schema to catch up before refusing, for the same class of reason.
- **The timeout is a chosen number with its reasoning**, and exceeding it is a real failure that still
  stops the deploy — the point is to distinguish *not yet* from *not going to*, not to wait forever.
- **The two failures must be distinguishable in the logs**, because they need different reactions:
  "gave up waiting for Postgres" is an infrastructure problem, "migration threw" is a code problem,
  and today both read as `MIGRATION FAILED`.
- Decide whether the wait belongs in the migrator itself or in an init container, and say why. The
  in-process form is consistent with `8-08`'s guard and works in the compose loop and a bare
  `dotnet run`; an init container is the more conventional Kubernetes answer and works for anything
  else that ever needs it. `8-08` chose in-process for the guard, and that reasoning is worth
  re-reading rather than assumed to transfer.

## Out of scope

- **Raising `backoffLimit`.** See above; it would silently undo a decision `8-08` argued for.
- **Ordering the deploy so Postgres is ready first.** Kustomize has no ordering primitive, which is
  the constraint `8-08` already worked around by making hosts refuse rather than by sequencing.
- **Anything about the schema guard on the three hosts.** It behaved correctly here and needs no
  change; its restart-until-ready loop is what made the failed migration survivable.

## Done when

- [ ] A migrator started against a Postgres that is not yet accepting connections waits and then
      succeeds, proven by starting it first — not by reading the code.
- [ ] A migrator started against a Postgres that never arrives exits non-zero within the timeout, with
      a message naming *waiting* as what failed rather than the migration.
- [ ] A genuinely failing migration still exits non-zero immediately, without waiting or retrying —
      the property `8-08` built and this item must not erode.
- [ ] `redeploy.md` no longer needs the reader to know that a deploy which restarts Postgres may
      require re-running the Job by hand.

## Open questions

**Whether `Connection refused` is the only shape of "not yet".** It was the observed one, but a
Postgres mid-restart can also accept a TCP connection and then refuse authentication, or answer
`the database system is starting up`. Enumerate what should be waited through and what should not,
because a wait that swallows an authentication failure turns a wrong password into a timeout, and
that is a worse error message than the one this item is fixing.
