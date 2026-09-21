# 26-03 · Operator device registration for push

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the first of four implementation items `26-01`'s own design
  (`docs/architecture/push-notifications.md`, `adr/0179`) named at its foot, split on promises per
  rule 15 rather than on code. The author's own instruction, 2026-09-21: start the backend rework
  that unblocks push for the Android app.
- **Depends on**: none. **This is the migration lane item** (CLAUDE.md rule 13) - only one migration
  in flight at a time across the three background lanes.

## What this item is

Everything `adr/0179` §1 decided, and nothing past it: a device can register, refresh its token, and
be revoked. **Nothing sends anything yet** - that is `26-04`/`26-05`.

## Scope

- **`OperatorDevice`**, a one-entity Domain aggregate root in `WebhookEndpoint`'s own shape. Identity
  is `unique (operator_id, installation_id)` - never the push token itself, which is a *value on* the
  row, replaced in place on rotation. A second, partial index - `unique (provider, token) where
  revoked_at is null` - stops one token being live on two rows (a restored device backup can cause
  this).
- **`operator_devices` table + EF migration.** `provider` is a real column from day one (`adr/0179`
  §5 - by-product of doing Android cleanly, not iOS preparation), and **the value written today is
  `"RuStore"`**, not `"Fcm"`: `adr/0180` changed the provider on 2026-09-21, before any adapter
  existed. That change is the column's own first piece of evidence for itself - it absorbed a
  provider swap with no migration and no Application-layer change.
- **`IOperatorDeviceRepository`** in `Ago.Chat.Application/Abstractions`, EF adapter in
  `Ago.Chat.Infrastructure.Postgres` - the dependency rule (CLAUDE.md rule 1): no `DbContext` in
  Domain or Application.
- **Two `Ago.Chat.Api` routes**: `PUT /api/v1/me/devices/{installationId}` (idempotent upsert - the
  whole rotation story, called on every sign-in, from `onNewToken`, and from a periodic client job)
  and `DELETE /api/v1/me/devices/{installationId}` (explicit revocation on sign-out - a step Android
  has and the console does not, since the console's own sign-out makes no backend call at all).
  `RequireOperatorIdentity` on both.
- **`13-03`'s existing `OperatorRemovedConsumer`** gains one call: revoke every device row for a
  removed operator.
- **`ON DELETE CASCADE` from `operator_devices.site_id`**, and confirm live (not assumed) that
  `SiteErasureQuery` actually reaches it - `adr/0168`'s own Consequences record this exact assumption
  failing once already (`25-78`), which is precisely why this item checks it up front rather than
  finding out later.

## Out of scope

- Anything that talks to the push provider (`26-04`).
- The fan-out consumers (`26-05`).
- The Android client's own registration call (`26-06`) - this item is the server side only.

## Done when

- [x] `operator_devices` exists via a real EF migration, with both indexes proven by a test that
      constructs the conflicting-row case for each.
- [x] The upsert route is idempotent - calling it twice with the same `installationId` and a new
      token updates the existing row, never inserts a second one.
- [x] The revoke route removes/marks-revoked the row, and a revoked device is provably invisible to
      whatever `26-05` will later query (state the shape of that query now, even unused).
- [x] `OperatorRemovedConsumer` revokes every device row for that operator - a real test, not a
      manual claim.
- [x] `SiteErasureQuery` is confirmed live to reach `operator_devices` via the cascade, or a
      compensating deletion is added if it does not.
- [x] `dotnet format`/`build`/`test` all green, full suite counts reported.

## Outcome

Landed as `ago-chat#350`. `OperatorDevice` (Domain), `operator_devices` (one EF migration) keyed on
`(operator_id, installation_id)` with a partial-unique `(provider, token)` index for the
restored-backup case; `IOperatorDeviceRepository` in Application/Abstractions, EF adapter in
Infrastructure.Postgres. `PUT`/`DELETE /api/v1/me/devices/{installationId}`, self-scoped,
`RequireOperatorIdentity`-gated; the `PUT` upsert also revokes any other row still holding the same
live token (the restored-backup edge case). `OperatorRemovedConsumer` gained a second call revoking
every device row for a removed operator, proven through the real outbox/RabbitMQ chain.

**Live cascade-deletion finding**: `SiteErasureQuery`'s declared `ON DELETE CASCADE` from
`sites`/`operators` reaches `operator_devices` with no compensating deletion needed - confirmed by a
real integration test, not assumed from `adr/0168`'s own different-table precedent.

**One correction caught before merge**: `adr/0180` (2026-09-21) replaced FCM with RuStore Push while
this item was mid-flight - `PushProvider`'s only member and every test fixture referencing it were
renamed from `Fcm` to `RuStore` before merging, so this item never shipped naming the wrong provider.

Verified independently, beyond the worker's own report: full suite green twice (once before, once
after the RuStore rename) - Domain 779, Application 1477, Architecture 52, Concurrency 90, Integration
1496, 0 warnings both times. CI green on the PR before merge.
