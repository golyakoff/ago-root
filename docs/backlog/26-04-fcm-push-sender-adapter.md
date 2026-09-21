# 26-04 · FCM push-sender adapter

- **Stage**: 26
- **Status**: needs a decision - blocked on the data-residency question below, not on design
- **Found**: 2026-09-21, the second of four implementation items `26-01`'s own design
  (`docs/architecture/push-notifications.md`, `adr/0179`) named at its foot.
- **Depends on**: `26-03` (needs `operator_devices` to read a token from - independent of `26-05`,
  can run in a second lane in parallel with it once `26-03` lands).

## The precondition this item does not get to skip

`adr/0179` §6 names two measurements this design deliberately did not pre-empt, and
`personal-data.md`'s own data-residency default is a third, separate gate that is the author's alone:

1. **Data residency.** FCM is a Google destination; `personal-data.md`'s default answer for a new
   destination is "in Russia," and moving one out is a decision made explicitly, in writing, with the
   legal question asked first (`adr/0179`, Consequences). **This item does not start writing an
   `Ago.Chat.Infrastructure.Fcm` project until the author has answered this.** Minimisation is already
   designed in regardless of the answer: no message body, no visitor identity beyond a truncated
   pseudonym, no conversation content (`adr/0179` §2).
2. **Network reachability.** `fcm.googleapis.com` and `oauth2.googleapis.com` from the live VPS node,
   measured by `adr/0070`'s own method (its `api.telegram.org` control run found 8 of 15 attempts
   never established TCP - not a hypothetical risk). If either needs a relay, the adapter gets a
   proxy-aware `HttpClient` wired in the composition root, exactly as `TelegramProxyOptions` already
   documents for Telegram.

Status stays `needs a decision` for measurement 1 specifically - a legal/product call, not a
technical one - even though `26-03` can and does proceed without it.

## Scope, once unblocked

- **`IPushSender`** in `Application/Abstractions`, taking a `PushMessage` (title, body, collapse key,
  a small data map) - never an FCM request shape (`adr/0179` §5: the port's vocabulary must not be
  the adapter's).
- **`Ago.Chat.Infrastructure.Fcm`**: one implementation, registered directly - no provider registry,
  no `IPushSenderFactory` (`adr/0179` §5 - a dispatch table with one entry is a guess about the
  second).
- **The service-account credential**: `FCM_SERVICE_ACCOUNT_JSON`, `infra-credentials`, rotation class
  **Restart**, trivially **Draining** (a service account may hold two keys at once). `secrets.md` and
  `tools/secrets-audit.sh` gain the new key in the same change, or the audit fails.
- **Resilience**: the same policy shape this codebase already proves for its six channel adapters
  (MAX, Telegram, VK, Avito, WhatsApp, Email) - timeout, retry, circuit breaker per
  `docs/architecture/resilience.md`.
- **Sends are data-only FCM messages, never `notification` payloads** (`adr/0179` §3) -
  `android.priority = "high"` for these two message kinds only.
- **Metrics**: `ago.chat.push.sends`, `ago.chat.push.suppressed`, `ago.chat.push.tokens_revoked` -
  no per-send audit table (`adr/0179`'s own Consequences: a durable log of who was told what, when is
  exactly the shape `personal-data.md` already rejected).
- A token answering `UNREGISTERED`/`INVALID_ARGUMENT` revokes its `26-03` row - the mechanism that
  actually keeps the table clean, per `adr/0179` §1.

## Out of scope

- The fan-out consumers that call this port (`26-05`).
- APNs, a provider registry, or any second `IPushSender` implementation - `adr/0179` §5 is explicit
  that none of this is built until a real iOS device registers.

## Done when

- [ ] The author's data-residency decision is recorded here, explicitly, before any adapter code
      lands - not inferred from silence.
- [ ] Reachability of both Google hosts from the live node is measured and recorded, by `adr/0070`'s
      own method - not assumed from an unrelated three-week-old control run.
- [ ] `IPushSender`/`PushMessage` exist in Application, with no FCM vocabulary leaking across the
      port.
- [ ] A real send is proven against the actual FCM service (or its emulator, if reachability forces
      a relay design first) - not only a unit test against a mocked `HttpClient`.
- [ ] A revoked/stale token is proven to update the `26-03` row, end to end.
- [ ] `secrets.md`/`tools/secrets-audit.sh` updated in the same change.
- [ ] `dotnet format`/`build`/`test` all green, full suite counts reported.
