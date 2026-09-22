# 26-05 · Push fan-out consumers

- **Stage**: 26
- **Status**: done — `ago-chat#353`; remainder carried out to `26-21`
- **Found**: 2026-09-21, the third of four implementation items `26-01`'s own design
  (`docs/architecture/push-notifications.md`, `adr/0179`) named at its foot.
- **Depends on**: `26-03` (device rows to read) and `26-04` (a real `IPushSender` to call for the
  end-to-end proof - the handler and consumers themselves can be built and unit-tested against a fake
  implementation of the port in the meantime).

## Scope

- **`NotifyOperatorDevicesHandler`** (Application), reusing `alerts.ts`'s own rules rather than
  inventing a second set: visitor messages only, the assigned operator only, `alertTextFor`'s text
  shape with **no message body** - the reason that file gives (a notification survives in a tray this
  system cannot erase).
- **Two `Competing` consumers in `Ago.Chat.Worker`**, each its own `ConsumerName`, queue and DLQ:
  - `OperatorAssignmentPushConsumer` on `ConversationAssignedToOperator` (transfers come free -
    `ConversationTransferredMapper` already maps onto this contract).
  - `OperatorMessagePushConsumer` on `MessageAccepted` (a fifth competing subscriber - confirm the
    per-subscriber queue name pattern from the existing four still holds).
- **No `inbox` idempotency row** (`adr/0020` permits direct publication for a derived, best-effort
  notification). **That refusal is unchanged; the mechanism under it moved** when `adr/0180` swapped
  the provider. RuStore has **no `collapse_key` on the wire** - its send schema has no such field,
  and its client-side `RemoteMessage.collapseKey` is documented as not currently taken into account -
  so this item no longer sends one. Idempotency is entirely client-side and entirely `26-18`'s:
  the notification tag `ago-conversation-{id}`, the identical value `useAlerts.ts` already uses,
  plus dedupe by message id. **What this item owes is the payload that makes both possible**: the
  conversation id and the message id in the data map, every time.
- **The server never suppresses on presence** (`adr/0179` §3, the question this whole design existed
  to settle) - a push fires whether or not the operator has a live desktop console. Write the test
  that proves this directly: a push fan-out fires even when `INodeFanoutPublisher`'s own registry
  shows the operator connected.
- Confirm live, not assumed, that a fifth `Competing` subscriber on `MessageAccepted` does not change
  ordering or duplicate delivery for the existing four.

## Out of scope

- The RuStore Push adapter itself (`26-04`) - this item calls `IPushSender`, it does not implement it.
- The Android client's own dedupe/rendering (`26-18`).
- Any push for a waiting-queue entry or a calendar booking deadline - `adr/0179`'s own "What this
  design deliberately leaves out" names both as real future work this item does not do.

## Done when

- [x] Both consumers exist, each with its own queue/DLQ, and a message-accepted event from the
      **visitor** side fires push while one from the **operator** side does not (matching
      `alerts.ts`'s own rule).
- [x] A conversation transfer produces a push to the new assignee, proven by a real test - not
      inferred from the mapper existing.
- [x] A push fires when the operator's own presence registry entry says connected - the explicit,
      deliberate non-suppression, proven rather than merely stated.
- [x] The payload carries the conversation id and the message id, so `26-18` can build
      `useAlerts.ts`'s own `ago-conversation-{id}` tag and dedupe from it. **No collapse key is
      sent** - RuStore has no such field (`adr/0180`), and asserting one would be inventing an API.
- [x] `dotnet format`/`build`/`test` all green, full suite counts reported.
- [~] A real send is proven end-to-end - **carried out to `26-21`**, the identical reason `26-04`'s
      own remaining boxes were: no RuStore Console project exists in this deployment yet.

## Outcome

Landed as `ago-chat#353`. `NotifyOperatorDevicesHandler` (Application) ports `alerts.ts`'s exact rules
server-side; two `Competing` consumers (`OperatorAssignmentPushConsumer`,
`OperatorMessagePushConsumer`), each its own queue/DLQ. The server-never-suppresses decision is
architectural, not a runtime check: the handler's constructor has no `IConnectionRegistry`/
`INodeFanoutPublisher` parameter to consult at all - proven live against a connection registry seeded
as connected. `OperatorMessagePushConsumer` is a real fifth subscriber on `MessageAccepted`, proven
alongside the existing four (real Postgres+RabbitMQ) to not change ordering or duplicate delivery.

**Two real bugs found and fixed by the implementing worker's own tests before this landed**: the new
handler's registration in the shared `ChatModule.ConfigureServices` broke `Ago.Chat.Api`'s DI graph
(`IPushSender` is `Ago.Chat.Worker`-only by design) - moved to `Program.cs`; and the handler's two
entry points needed `TenantScopeExemptions` entries, caught by `TenantScopeTests`.

Verified independently, beyond the implementing worker's own report: `dotnet format`/`build -c
Release` clean (0 warnings); full suite - Domain 787, Application 1506, FakeCrm 21, Architecture 53,
Concurrency 90, Integration 1508/1509 (one failure, the same pre-existing `SchemaMigratorTests`
Testcontainers-readiness flake seen once already this session, under this machine's own unusually
heavy concurrent load from running several parallel builds and an Android emulator at once - re-ran
that one test alone afterward, 9/9 clean; not filed as its own item since it appears to be an artifact
of this session's own unusual concurrency, not a product defect).
