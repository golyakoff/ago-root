# 26-82 · Concurrent device registration throws a duplicate-key error instead of upserting

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, by the author, live on the demo stand — reported as "the message reaches the
  dialog list very slowly" while testing `26-06`'s push registration on a real phone. Investigated by
  reading `Ago.Chat.Api`'s real pod logs on the live demo cluster: not the cause of that particular
  symptom, but a real, separate bug found in passing while looking for it.

## What is actually true today, confirmed against real logs and code

`RegisterOperatorDeviceHandler.HandleAsync` (`ago-chat`) does a plain check-then-act upsert:

```csharp
var existing = await devices.FindAsync(command.OperatorId, command.InstallationId, cancellationToken);
if (existing is null) { /* INSERT via OperatorDevice.Register */ }
else { /* UPDATE via existing.Refresh(...) */ }
```

`26-06`'s own Android client calls `PUT /api/v1/me/devices/{installationId}` from **three** places that
can genuinely race each other for the identical `(operatorId, installationId)` pair: sign-in,
`onNewToken`, and a periodic `WorkManager` job — all three plausibly close together right after an app
launch or a token rotation. When two calls both read `existing == null` before either has committed
(the classic check-then-act race), both attempt an `INSERT`, and the second throws:

```
Npgsql.PostgresException (0x80004005): 23505: duplicate key value violates unique constraint
"ux_operator_devices_operator_installation"
```

Observed live on the demo cluster, `Ago.Chat.Api` pod logs, 2026-09-24 ~07:53 UTC — 9 occurrences in a
30-minute window from one real device's own registration attempts. The exception is a
`DbUpdateException`, which `RegisterOperatorDeviceHandler`'s own `catch` clause does not handle (it
only catches `ArgumentException` for domain validation failures) — so it propagates as an unhandled
500. `KtorDeviceRegistrationApi.register()`'s own catch-all classifies any non-2xx/thrown response as a
plain `false`, so the client silently treats a raced-out registration as "did not happen this time" with
no retry and no visible signal to the operator that their device's token may now be stale.

## Scope

- Make the upsert race-safe: either a real `INSERT ... ON CONFLICT (operator_id, installation_id) DO
  UPDATE` at the EF Core/SQL level, or catch the specific `DbUpdateException` wrapping a `23505` on
  `ux_operator_devices_operator_installation` and retry once as an update (the identical shape
  `MessageBatchWriter`'s own bounded-retry-on-concurrency-conflict already uses elsewhere in this
  codebase, `25-109`).
- A unit/integration test that fires two concurrent `HandleAsync` calls for the same
  `(operatorId, installationId)` and asserts both succeed with one row surviving, not one throwing.

## Out of scope

- Anything about push delivery latency itself — that's a separate, still-open investigation from the
  same live-testing session, not caused by this bug.
- The Android client's own retry/backoff behavior on a failed registration — this item only fixes the
  server-side race; whether the client should also retry more assertively is a separate question if it
  turns out to matter after this fix.

## Done when

- [ ] Two concurrent registration calls for the same `(operatorId, installationId)` both succeed —
      proven by a real concurrent test, not by inspection.
- [ ] `dotnet format`/`build`/`test` green.
