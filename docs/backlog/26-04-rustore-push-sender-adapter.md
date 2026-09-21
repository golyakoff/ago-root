# 26-04 · RuStore Push sender adapter

- **Stage**: 26
- **Status**: ready - **the data-residency gate is resolved, not merely relaxed** (see below)
- **Found**: 2026-09-21, the second of four implementation items `26-01`'s own design
  (`docs/architecture/push-notifications.md`, `adr/0179`) named at its foot.
- **Retitled**: 2026-09-21. This item was `26-04 · FCM push-sender adapter` until `adr/0180` changed
  the provider to **RuStore Push**. Same promise, same port, same position in the dependency chain;
  a different adapter behind it.
- **Depends on**: `26-03` (needs `operator_devices` to read a token from - independent of `26-05`,
  can run in a second lane in parallel with it once `26-03` lands).

## The gate that is closed, and the one that replaces it

`adr/0179` §6 named two measurements, and `personal-data.md`'s residency default was a third gate
that was the author's alone. **The third is settled and this item is no longer blocked on it.**

**Data residency: resolved.** `personal-data.md`'s default answer for a new destination is "in
Russia", and moving one out is a decision made explicitly, in writing, with the legal question asked
first. `adr/0180` settles it by **satisfying the default rather than escaping it**: RuStore Push is
Russian infrastructure, so there is no written legal escalation to obtain and nothing here waits on
one. The author took that decision on 2026-09-21, accepting in his own words a less documented SDK
that has to be researched from scratch. Minimisation is unchanged and still designed in: no message
body, no visitor identity beyond a truncated pseudonym, no conversation content (`adr/0179` §2).

**Network reachability: still a real gate, on one host instead of two.** `vkpns.rustore.ru` from the
live VPS node, by `adr/0070`'s own method - N requests, spaced, fixed timeout, **a deliberately
invalid service token so an HTTP 403 `PERMISSION_DENIED` proves a complete round trip** (that is
RuStore's own documented code for a bad service key; the FCM version of this item used a 401). There
is no OAuth2 mint, so there is no second host. `adr/0070`'s `api.telegram.org` run found 8 of 15
attempts never established TCP from this VPS, so this is not a hypothetical; if a relay is needed,
the adapter gets a proxy-aware `HttpClient` wired in the composition root exactly as
`TelegramProxyOptions` already documents.

**`adr/0070`'s control run is *less* relevant here than it was under FCM, not more.** It measured a
Google host from this VPS. A Russian host reached from a Russian VPS is a different question and that
data says nothing about it - do not cite it as reassurance.

## Scope

- **`IPushSender`** in `Application/Abstractions`, taking a `PushMessage` (title, body, grouping key,
  time-to-live, a small data map) - never a provider request shape (`adr/0179` §5: the port's
  vocabulary must not be the adapter's). `adr/0180` is that rule's first piece of evidence: the
  provider changed before a line of this adapter existed and the port's signature did not move.
- **`Ago.Chat.Infrastructure.RuStore`**: one implementation, registered directly - no provider
  registry, no `IPushSenderFactory` (`adr/0179` §5 - a dispatch table with one entry is a guess about
  the second).
- **The send call**, exactly as RuStore documents it:
  `POST https://vkpns.rustore.ru/v1/projects/{projectId}/messages:send`, with
  `Authorization: Bearer {service-token}` and a `{"message": {...}}` body.
- **The credential**: `RUSTORE_PUSH_SERVICE_TOKEN` in `infra-credentials`, read by `Ago.Chat.Worker`
  alone. Rotation class **Restart** - and unlike the FCM version of this item, **`Draining` is not
  claimed**, because RuStore's documentation does not say whether a push project can hold two live
  service tokens. Find out in the console and record the answer here; do not assert it.
  `secrets.md` and `tools/secrets-audit.sh` gain the key in the same change, or the audit fails.
  **The project ID is not a secret** - it ships in the app's own `AndroidManifest.xml` - but it is
  still deploy-time configuration rather than a committed value, since these repositories are public.
- **Resilience**: the same policy shape this codebase already proves for its six channel adapters
  (MAX, Telegram, VK, Avito, WhatsApp, Email) - timeout, retry, circuit breaker per
  `docs/architecture/resilience.md`. `429 TOO_MANY_REQUESTS` is absorbed by that policy on judgement,
  because **RuStore documents the error and not its threshold**; claim no throughput figure.
- **Sends are data-only messages, never `notification` payloads** (`adr/0179` §3, unchanged by
  `adr/0180`). RuStore's own SDK doc is explicit that a non-empty `notification` is rendered by the
  SDK itself with no app code consulted, and that `onMessageReceived` fires *in any case* - which is
  what makes `decideAlert`-on-the-client implementable at all. **There is no `priority` field to
  set**: RuStore's schema has none and its client-side `RemoteMessage.priority` is documented as not
  currently taken into account, so the FCM-era `android.priority = "high"` line is deleted rather
  than translated.
- **`android.ttl` is set explicitly and short.** RuStore's default when it is absent or zero is
  **four weeks**, which for "a visitor is waiting" is noise rather than a notification. **Choose the
  number in this item and state the reasoning** - `26-01` deliberately did not pick one, because this
  project does not invent numbers.
- **Settle the `message.data.payload` ambiguity with a real send.** RuStore's published validation
  rule reads *"if `message.data.payload` is present and non-empty"* while `message.data` is typed in
  the same document as a flat `map[string]string`. Whether a data-only message needs a key literally
  named `payload` is **not answerable from the documentation** - the first real send answers it, and
  the answer goes in `push-notifications.md`.
- **Metrics**: `ago.chat.push.sends`, `ago.chat.push.suppressed`, `ago.chat.push.tokens_revoked` -
  no per-send audit table (`adr/0179`'s own Consequences: a durable log of who was told what, when is
  exactly the shape `personal-data.md` already rejected).
- **Terminal errors revoke the `26-03` row; nothing else does.** RuStore's documented outcomes:

  | Outcome | HTTP | `status` | Treatment |
  |---|---|---|---|
  | Malformed push token | 400 | `INVALID_ARGUMENT` | **Terminal** - revoke |
  | Valid token, expired | 404 | `NOT_FOUND` | **Terminal** - revoke |
  | Bad service key | 403 | `PERMISSION_DENIED` | **Never** a device fault - this is our credential, and treating it as one would revoke the whole table the first time the token was rotated wrong |
  | Rate limited | 429 | `TOO_MANY_REQUESTS` | Transient |
  | Service error | 500 | `INTERNAL` | Transient |

  **Key on `status`/`code`, never on `message`.** RuStore's own published example of a
  malformed-token response carries the text *"The registration token is not a valid FCM registration
  token"* - a Firebase string inside a RuStore error body, consistent with RuStore calling the API a
  drop-in replacement for Firebase, and a good reason to trust the enumerated field over the prose
  one. Treat `UNREGISTERED` as terminal if it ever arrives (it appears in the `status` field's own
  example list but not in the enumerated error list) without depending on it.

## Out of scope

- The fan-out consumers that call this port (`26-05`).
- Anything on the phone (`26-06`, `26-18`) - including measuring delivery latency, which is `26-18`'s
  because it needs a real device.
- APNs, a provider registry, or any second `IPushSender` implementation - `adr/0179` §5 is explicit
  that none of this is built until a real iOS device registers.
- RuStore's **Universal** push API (`vkpns-universal.rustore.ru`). `adr/0180` names it and declines
  it: it reaches FCM as a fallback, which puts back the destination this whole change removed, and it
  carries each provider's credentials in the request body, which would mean this Worker holding a
  Google service account after all. It is the named reopening point if `26-18`'s prerequisite or
  latency measurements come back badly - not something to reach for here.

## Done when

- [ ] Reachability of `vkpns.rustore.ru` from the live node is measured and recorded, by `adr/0070`'s
      own method - not assumed, and not inferred from that ADR's Google control run.
- [ ] `IPushSender`/`PushMessage` exist in Application, with no RuStore vocabulary leaking across the
      port.
- [ ] A real send is proven against the actual RuStore service - not only a unit test against a
      mocked `HttpClient`. Note that the SDK's own `testModeEnabled` path **does not touch the
      backend at all**, so a test-mode push proves nothing about this item.
- [ ] The `message.data.payload` ambiguity is settled by that send, and the answer is written into
      `docs/architecture/push-notifications.md`.
- [ ] A revoked/stale token is proven to update the `26-03` row end to end, and a `403` is proven
      **not** to - the second matters more, because getting it wrong empties the table silently.
- [ ] `android.ttl` is set, and the chosen value and its reasoning are recorded here.
- [ ] Whether a push project can hold two live service tokens is answered from the console, and the
      rotation class in `push-notifications.md` and `secrets.md` reflects the real answer.
- [ ] `secrets.md`/`tools/secrets-audit.sh` updated in the same change.
- [ ] `dotnet format`/`build`/`test` all green, full suite counts reported.
