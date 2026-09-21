# 26-05 · Push fan-out consumers

- **Stage**: 26
- **Status**: ready - the code can be written and tested against a fake `IPushSender` before `26-04`
  is unblocked; only the real end-to-end proof needs `26-04` to have landed for real.
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
  notification). Idempotency is a collapse key per conversation - `ago-conversation-{id}`, the
  identical value `useAlerts.ts` already uses as its own `Notification` tag - plus client-side
  dedupe by `MessageId` (the Android half, `26-06`).
- **The server never suppresses on presence** (`adr/0179` §3, the question this whole design existed
  to settle) - a push fires whether or not the operator has a live desktop console. Write the test
  that proves this directly: a push fan-out fires even when `INodeFanoutPublisher`'s own registry
  shows the operator connected.
- Confirm live, not assumed, that a fifth `Competing` subscriber on `MessageAccepted` does not change
  ordering or duplicate delivery for the existing four.

## Out of scope

- The FCM adapter itself (`26-04`) - this item calls `IPushSender`, it does not implement it.
- The Android client's own dedupe/rendering (`26-06`).
- Any push for a waiting-queue entry or a calendar booking deadline - `adr/0179`'s own "What this
  design deliberately leaves out" names both as real future work this item does not do.

## Done when

- [ ] Both consumers exist, each with its own queue/DLQ, and a message-accepted event from the
      **visitor** side fires push while one from the **operator** side does not (matching
      `alerts.ts`'s own rule).
- [ ] A conversation transfer produces a push to the new assignee, proven by a real test - not
      inferred from the mapper existing.
- [ ] A push fires when the operator's own presence registry entry says connected - the explicit,
      deliberate non-suppression, proven rather than merely stated.
- [ ] The collapse key matches `useAlerts.ts`'s own `ago-conversation-{id}` tag exactly.
- [ ] `dotnet format`/`build`/`test` all green, full suite counts reported; a real send is proven
      end-to-end once `26-04` is unblocked (record the date this box was actually ticked if it lags
      the rest of the item).
