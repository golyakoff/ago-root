# Push notifications to an operator's phone

> **Status: designed, not built.** `26-01`, 2026-09-21. Every mechanism on this page is a design.
> Nothing here exists in `Ago.Chat.*` today — no table, no port, no consumer, no credential. The
> paragraph *[What is true today](#what-is-true-today)* is the only part of this file that describes
> running code, and it says that the only way an operator learns anything is a live SignalR
> connection. Read the rest as intent, the way `docs/backlog/` is read. The decision behind it is
> [`adr/0179`](../adr/0179-operator-push-is-a-worker-fan-out-to-a-device-row-and-the-loudness-decision-stays-on-the-client.md).
>
> **When it ships, the first section gets rewritten and this banner comes off.** Until then a reader
> who wants to know what the system does now should stop after the next heading.

## What is true today

Confirmed by reading the code on 2026-09-21, not from memory.

**The console's alerting is the browser's `Notification` API and nothing else.**
`ago-console/src/workspace/alerts.ts` holds every decision as pure functions; `useAlerts.ts` holds
the effects — constructing a `Notification`, synthesising a two-tone chime through `AudioContext`.
Two switches (`notifications`, `sound`), both off until the operator turns them on, persisted in
`localStorage` under `ago.console.alerts`. `decideAlert` fires unless *this tab has that conversation
open **and** `document.visibilityState === "visible"`*. `alertTextFor` composes the text and
deliberately **never includes the message body** — a privacy decision, argued in that file, because a
desktop notification is drawn over whatever is on screen and survives in a notification centre
nothing in this system can erase.

**Exactly two things make it loud**, both installed as hub handlers in `WorkspaceLayout.tsx`:

| Trigger | Hub push | Call site |
|---|---|---|
| A conversation was assigned to this operator | `ConversationAssigned` | `fire("assigned", dto.conversationId, null)` |
| A **visitor** message arrived on any conversation assigned to this operator | `MessageReceived` | `fire("message", conversationId, visitorId)` |

The message path filters `message.authorKind !== "Visitor"` and skips the conversation already open,
before `decideAlert` ever runs.

**All of it requires the tab to be open and the SignalR connection live.** There is no server-side
delivery path of any kind for a person who is not connected.

**There is no push infrastructure anywhere.** A fresh grep across `ago-chat`, `ago-calendar`,
`ago-console`, `ago-widget` and `ago-deploy` for `fcm|firebase|apns|devicetoken|pushnotification`
returns nothing outside a Razor build cache and two compressed git objects. `ago-platform` is not
checked out in this workspace; its published package set is `Abstractions`, `Caching.Redis`,
`Hosting`, `Kernel`, `Messaging.RabbitMq`, `Observability`, `Persistence.Postgres`, `Realtime`,
`Resilience`, `Storage.S3` — no push package exists to have used.

### The server-side signals that already exist, by name

The brief for this design assumed four alert-worthy cases. Three have a real integration event
already; one does not exist at all, and that is a finding rather than a gap to fill here.

| Case | Existing server-side signal | Verdict |
|---|---|---|
| A conversation was assigned | **`Ago.Chat.Contracts.ConversationAssignedToOperator`**, outboxed from `Ago.Chat.Domain.ConversationAssigned` by `ConversationAssignedToOperatorMapper`. Carries `ConversationId`, `SiteId`, `VisitorId`, **`OperatorId`**, `CorrelationId`, `OccurredAt` | Ready. Nothing new needed |
| A conversation was **transferred** to this operator | The same contract — `ConversationTransferredMapper` maps `ConversationTransferred` onto `ConversationAssignedToOperator` too | Ready, and covered **for free**. The console already alerts on it for the same reason |
| A visitor sent a message on an assigned conversation | **`Ago.Chat.Contracts.MessageAccepted`**, outboxed from `MessageAdded`. Carries `MessageId`, `SiteId`, `ConversationId`, `AuthorKind`, `Sequence`, `CorrelationId`, `OccurredAt`. Deliberately **no body** | Ready, but it does not name an operator — the conversation has to be loaded to find one, exactly as `ResolveMessageDeliveryTargetsHandler` already does |
| A conversation entered the **waiting queue** | **Nothing.** There is no `ConversationStarted` contract and no mapper for one. `realtime.md` states it in so many words: "nothing broadcasts 'a new conversation started waiting' to every operator of a site (only the operator it eventually gets assigned to ever hears about it)" — the console's own waiting list is a 10-second poll | **No signal exists**, and the console does not alert on this either. Out of scope, see [What this design deliberately leaves out](#what-this-design-deliberately-leaves-out) |
| A pending booking nearing its confirm-by deadline | `Ago.Calendar.Contracts.BookingPendingStateChanged` exists — **in a different product, a different repository and a different database**, with no consumer in `ago-chat` and no chat-side recipient. AGO Calendar has its own console and its own fan-out to its own tenant principals | Out of scope. `adr/0027`'s own boundary; a chat push for a calendar event would be the cross-product coupling that boundary exists to prevent |

The first two rows are the whole of what this design fans out, and they are exactly the two things
`alerts.ts` is already loud about. That is not a coincidence — reusing the console's own rule rather
than inventing a second one is the point.

---

## The shape

```
Ago.Chat.Api                          Ago.Chat.Worker
  PUT    /api/v1/me/devices/{iid}       OperatorAssignmentPushConsumer  <- ConversationAssignedToOperator
  DELETE /api/v1/me/devices/{iid}       OperatorMessagePushConsumer     <- MessageAccepted
        |                                          |
        v                                          v
  IOperatorDeviceRepository  <------------ NotifyOperatorDevicesHandler
        |                                          |
        v                                          v
  operator_devices (Postgres)                  IPushSender
                                                   |
                                                   v
                                        Ago.Chat.Infrastructure.Fcm
                                                   |
                                                   v
                                        fcm.googleapis.com  ->  the phone
```

`Ago.Chat.Webhooks` is untouched. `ago-console` is untouched. **No new host** — see
[Which hosts change](#which-hosts-change).

---

## Device registration

### The row

One new table, `operator_devices`. One row per **(operator, app installation)** — never one row per
token, which is the single decision that makes token rotation work at all.

| Column | Type | Why |
|---|---|---|
| `id` | `uuid` pk | |
| `site_id` | `uuid not null`, FK → `sites(id)` | Tenant scope is a fact on the row, not a join. Also what makes site erasure cascade for free (see [Erasure](#erasure-and-what-google-keeps)) |
| `operator_id` | `uuid not null`, FK → `operators(id)` | The fan-out's own lookup key — `ConversationAssignedToOperator` already carries exactly this |
| `installation_id` | `text not null` | The client-generated, stable-per-install identifier. **This, with `operator_id`, is the row's identity** |
| `provider` | `text not null` | `'fcm'` today. See [The iOS boundary](#the-iosapns-boundary) |
| `platform` | `text not null` | `'android'` today — diagnostic, not routing |
| `token` | `text not null` | The FCM registration token. A **value on** the row, replaced in place on every refresh |
| `created_at` | `timestamptz not null` | |
| `last_seen_at` | `timestamptz not null` | Rewritten on every re-registration. What an operational query sorts by to find dead installs |
| `revoked_at` | `timestamptz null` | Set on sign-out, on operator removal, or when the provider says the token is gone |
| `last_failure_at` | `timestamptz null` | |
| `failure_reason` | `text null`, bounded | The provider's own short error code. Bounded for the identical reason `ChannelDelivery.MaxProviderDetailLength` is: a failure reason is a code or a phrase, never an essay |

Indexes:

- `unique (operator_id, installation_id)` — the identity. An upsert target.
- `unique (provider, token) where revoked_at is null` — partial. A token must never be live on two
  rows. It can genuinely happen: a device backup restored onto a second phone, or an app reinstall
  that inherits a token. Without this the same buzz goes to two rows and a revocation clears only one.
- `(operator_id) where revoked_at is null` — the fan-out's own read.

**One operator per site, not one identity across sites.** A Keycloak identity may hold several
`Operator` rows — `operators` is uniquely indexed on `(external_subject_id, site_id)`, and
`GET /api/v1/me/tenancies` exists precisely because one person can work for several tenants. A device
therefore registers **once per tenancy the app is signed into**, and one physical phone can hold two
rows. The alternative — one row per identity, resolved to devices through `external_subject_id` — was
rejected: the fan-out events name an `OperatorId`, so that shape would add a lookup to the hot path
to arrive at the same answer, and it would mean a notification about tenant A reaching a device the
operator registered while working for tenant B. `tenant-isolation.md`'s whole claim is that every
piece of data is scoped by `site_id`; a notification is a piece of data.

### Why this is not an aggregate with invariants, and is still a Domain type

`Ago.Chat.Domain.OperatorDevice` — a small aggregate root of exactly one entity, in the shape
`WebhookEndpoint` already has. It is a Domain type because it owns two real rules that must not live
in a handler: a token has a bounded length and may not be blank (the same bounded-value discipline
`MessageBody` and `ChannelDelivery.MaxProviderDetailLength` apply), and *a revoked device sends
nothing until a fresh registration revives it*. It is **not** a type with children or a state machine:
there are two mutations, `Refresh` and `Revoke`, both idempotent.

*The layering call, stated because this project asks for it:* the type is in Domain rather than a
bare row in Infrastructure because "a revoked device is silent" is a rule about the product, not
about Postgres — the alternative, a nullable column a query happens to filter on, puts that rule in
every caller's `WHERE` clause and it drifts the first time someone writes a second query.

### Registration and rotation

FCM tokens are **not stable**. They rotate on app reinstall, on restore to a new device, on app data
being cleared, and periodically at Google's own discretion. A design that treats a token as an
identifier accumulates one dead row per rotation, for ever.

So registration is an **idempotent upsert on `(operator_id, installation_id)`**:

```
PUT /api/v1/me/devices/{installationId}
    body: { provider, platform, token }
    auth: RequireOperatorIdentity          (a resolved OperatorId + SiteId claim pair)
    -> 204
```

`PUT`, not `POST`, because the client supplies the identity and the call must be safe to repeat.
The handler:

1. Revokes any other **live** row holding this exact `(provider, token)` — the restored-backup case.
2. Upserts `(operator_id, installation_id)`: writes `token`, sets `last_seen_at`, clears
   `revoked_at`, `last_failure_at`, `failure_reason`.

The Android client calls it in three places, and all three matter: **on every sign-in**, **from
`FirebaseMessagingService.onNewToken`** (Google's own rotation callback — the only event that can
tell the app its token changed), and **on a schedule the app itself sets** (a `WorkManager` job,
because `onNewToken` is not guaranteed to fire if the app was not running when the rotation
happened). The third one is what turns `last_seen_at` into a usable liveness signal rather than a
record of the last sign-in.

**Nothing on the server ever expires a row on a timer.** A phone in a drawer for three weeks is not a
revoked device, and guessing otherwise silences somebody's notifications for a reason they cannot
see. Rows go dead by exactly two mechanisms, both of which are facts rather than guesses: an explicit
revocation, or the provider itself saying the token is gone (below).

### Revocation

Three paths, and the first one is the one that is easy to get wrong.

**Sign-out, that device only.**

```
DELETE /api/v1/me/devices/{installationId}
    auth: RequireOperatorIdentity
    -> 204   (also 204 when there is no such row — DELETE is idempotent)
```

Called by the Android client **before** it discards its access token, because after that it cannot
authenticate the call. It sets `revoked_at` on exactly the one row for this installation, leaving
every other device this operator ever signed into alone.

This is a real cost worth naming: **the console's sign-out makes no backend call at all.**
`ago-console/src/auth/AuthProvider.tsx` calls `oidc-client-ts`'s `signoutRedirect()` and nothing
else — there is no server-side session to end. The Android client therefore has a sign-out step the
console does not, and "the user force-quit the app / cleared data / the phone was wiped" produces a
row that is never revoked by this path. That case is covered by the next one, not by this one, and a
design that pretended otherwise would leave a stranger's phone buzzing about a tenant's visitors.

**The provider says the token is gone.** FCM answers a send to a dead token with
`UNREGISTERED` (`404`) or `INVALID_ARGUMENT` (`400`). Both are terminal: the token will never work
again. The sender reports that outcome and the handler calls
`IOperatorDeviceRepository.RevokeByTokenAsync(provider, token, reason)`. **This is the mechanism that
actually keeps the table clean**, and it is the reason the table needs no sweep job: Google tells us,
on the next send, and we believe it. A transport failure (`UNAVAILABLE`, `INTERNAL`, a timeout) is
*not* terminal and never revokes anything — it records `last_failure_at`/`failure_reason` and
retries.

**The operator was removed from the site.** `13-03`'s existing `OperatorRemovedConsumer` already
consumes `OperatorRemovedFromSite` and releases that operator's conversations. It gains one more call
— revoke every device row for that `(operator_id)`. A new consumer for this would be a second
subscriber to one contract for one extra repository call; the existing one is already `Competing`,
already idempotent by the same `adr/0020` reasoning, and already in the right place.

---

## Fan-out

### Two consumers, one handler

Matching the shape `Ago.Chat.Worker` already uses everywhere — one `BackgroundService` per
(contract, purpose), each with its own stable `ConsumerName` so it gets its own queue and its own
DLQ, each calling one Application handler that holds the actual decision.

| Consumer | Subscribes | Mode | DLQ |
|---|---|---|---|
| `OperatorAssignmentPushConsumer` | `ConversationAssignedToOperator` | `Competing` | `operator-assignment-push.dlq` |
| `OperatorMessagePushConsumer` | `MessageAccepted` | `Competing` | `operator-message-push.dlq` |

`Competing`, not `Broadcast`, for the identical reason every consumer beside them is: exactly one
`Worker` replica needs to send each push. A `Broadcast` subscription would buzz the phone once per
replica.

`MessageAccepted` already has four competing consumers (`UnreadCounterConsumer`,
`ConnectionFanoutConsumer`, `OfflineAutoReplyConsumer`, `ChannelMessageDeliveryConsumer`); this is a
fifth, and a fifth is not a smell — it is what a stable `ConsumerName` per subscriber exists to make
safe.

`NotifyOperatorDevicesHandler` (`Ago.Chat.Application`) holds everything that decides. The consumers
deserialize, scope, call, ack — the same twenty lines `ConversationAssignmentFanoutConsumer` already
is.

### What the handler decides, and what it refuses to decide

**For an assignment**, everything needed is already on the contract: `OperatorId`, `ConversationId`,
`SiteId`, `VisitorId`. No load at all — the same "the event already names both recipients" property
`ResolveConversationAssignmentTargetsHandler` relies on.

**For a message**, three filters, and each one is `alerts.ts`'s own rule rather than a new one:

1. `AuthorKind == Visitor`. An operator's own echoed-back send is not news. This is the console's own
   first filter, verbatim (`message.authorKind !== "Visitor"` → return).
2. The conversation must have an assigned operator. `MessageAccepted` carries no operator, so the
   conversation is loaded through `IConversationRepository`, exactly as
   `ResolveMessageDeliveryTargetsHandler` does for the same event.
3. The only recipient is that operator. The console never alerts anybody else, and neither does this.

Then: load that operator's live device rows, and send one push per row.

**The text is `alertTextFor`'s text**, and the body rule is carried over without amendment: **never
the message body.** A push is drawn over a lock screen, in a shop, with customers in the room, and it
survives in a notification tray this system cannot reach. `alerts.ts` argued that for the desktop; a
phone makes the argument stronger, not weaker. What goes to Google is a title, a body naming the
visitor's eight-character pseudonymous id, and the conversation id.

### The question this design exists to answer: does a push fire when the operator is at their desk?

**Yes. Always. The server never suppresses a push because the operator looks connected.**

Four reasons, in the order they decided it.

**1. The registry is advice, not truth — by its own contract, in writing.** `realtime.md`:
"Registry contents are **advice**, not truth… Any logic that would corrupt data because the registry
was stale is a bug in that logic." Suppressing a push because Redis held a `presence:operator:{id}`
entry is precisely such logic. The entry survives its owner by up to one heartbeat TTL; a crashed
`Api` pod's entries survive until they expire, because `RemoveNodeAsync` is *still not wired to a
shutdown hook* (`realtime.md`, `3-06`). Building the product's most important feature on a value the
architecture document explicitly calls unreliable would be a defect, not a trade.

**2. A live connection is not an operator looking at the screen, and the server cannot tell the
difference.** `decideAlert`'s own rule needs `document.visibilityState`, which exists only inside the
browser and is never sent anywhere. Making the server able to answer would mean a new hub method —
adding a parameter to an existing one is forbidden (`realtime.md`: "a hub method's parameter count is
a contract, and it may never change", learned through two live outages) — plus a new piece of
per-connection mutable state, written on every tab switch, into the store already declared lossy. New
machinery, to make a worse decision.

**3. The failure modes are not comparable.** Suppress wrongly and the operator is *never told* —
which is the exact failure the Android app exists to fix, and is invisible when it happens. Fail to
suppress and a phone buzzes while its owner is already reading the thread — a mild annoyance, visible
the instant it happens, and one the operator can end themselves.

**4. The operator already has a better instrument than a server guess.** Android notification
channels, per-channel importance, Do Not Disturb, and the app's own Settings screen (`26-00`'s
`scope-inventory.md` already names it) all live on the phone, where the person is. "Do not disturb me
right now" is a decision for a human holding a device, not a server inferring from a WebSocket.

**But suppression does happen — on the device, by `alerts.ts`'s own rule.** This is the part that
makes the answer honest rather than merely convenient. FCM messages are sent as **data-only messages,
never `notification` payloads.** A `notification` payload is rendered by the Android system with no
app code running; a data message wakes `FirebaseMessagingService`, and the app decides. So the app
applies the identical rule the console applies — *is this conversation open on this screen, and is
this screen actually in front of the user?* — and stays silent when it is. `decideAlert`'s logic is
reused, not duplicated: it simply runs on each client, which is where `alerts.ts` put it in the first
place.

The rule, stated once: **the server decides who is told; each client decides whether to be loud.**

Two costs of data-only messages, both real:

- They need `android: { priority: "high" }` to escape Doze promptly. Normal-priority data messages
  are batched until the device next wakes, which for a phone in a pocket is exactly the wrong
  behaviour. High priority is not free — Google throttles apps that overuse it — so it is set only
  for these two message kinds and nothing else.
- If the app is force-stopped by the user, no data message reaches it at all. That is Android's rule,
  not a design choice, and no payload shape changes it.

### Idempotency, without an inbox row

Rule 5 says consumers are idempotent; at-least-once means a redelivered `MessageAccepted` would reach
this consumer twice.

**No `inbox` ledger.** `adr/0020` already permits this for "a purely derived, best-effort
notification computed from an already-outboxed event", which is exactly what a push is. Idempotency
comes from two mechanisms that are already the product's own:

- **A collapse key per conversation** — `ago-conversation-{conversationId}`, the identical value
  `useAlerts.ts` already uses as its `Notification` `tag`, for the identical reason ("a visitor
  sending four messages replaces its own card rather than stacking four"). FCM collapses undelivered
  messages sharing one key; Android's notification manager collapses delivered ones by tag. A
  redelivery replaces its own notification rather than adding one.
- **Client-side dedupe by `MessageId`**, which the data payload carries — the same dedupe-by-message-id
  the widget already does for redelivered broker messages (`messaging.md`).

That is idempotent *in effect*, which is what the rule asks for. An `inbox` row per push would add a
database write to every notification to prevent a duplicate the collapse key already prevents.

*The honest limit:* a redelivery separated by more than the user's own dismissal will buzz twice. It
is a buzz, not a corrupted counter, and `RecordUnreadMessageHandler` — which does maintain real
state — keeps its `IInboxChecker` row exactly as it has since `2-05`.

### Ordering

Rule 6 guarantees order per conversation and never globally, and this path needs neither. A push says
"something new happened in conversation X", never "here is message 7" — there is no sequence to get
wrong, and the collapse key deliberately makes the *latest* push the surviving one, which is the
correct semantic for a notification.

---

## The port, and what crosses it

```
Ago.Chat.Application/Abstractions
    IOperatorDeviceRepository      Upsert / Revoke / RevokeByToken / ListActiveForOperator
    IPushSender                    Task<PushSendOutcome> SendAsync(PushMessage, CancellationToken)
    PushMessage                    (DeviceToken, Title, Body, CollapseKey, Data)
    PushSendOutcome                Delivered | TokenGone(reason) | TransientFailure(reason)

Ago.Chat.Infrastructure.Postgres   OperatorDeviceRepository        (EF Core — a write store)
Ago.Chat.Infrastructure.Fcm        FcmPushSender                   (HTTP, Google OAuth2, resilience)
```

*Why a port at all, stated for the teaching record:* rule 2 — FCM is an external resource, so
`HttpClient` may not appear in Application, and the handler must be testable with a fake that returns
`TokenGone` without a network. The alternative, calling an FCM SDK from the handler, would make the
revocation-on-`UNREGISTERED` rule — the one rule that keeps the table from rotting — untestable
without Google.

*Why `IOperatorDeviceRepository` is EF and not a Dapper read store:* the fan-out both **reads**
tokens and **writes** revocations, in the same flow, for a row with an invariant
(`adr/0004` puts writes behind EF). A separate Dapper read store for a handful of rows keyed by one
indexed column would be a second port for the same table with no query it can express better —
the same judgement `ListMyTenanciesHandler` already records for its own small read.

*Why the resilience lives in the adapter:* `resilience.md`'s established shape and
`IWebhookDeliveryClient`'s own remarks — per-endpoint timeouts, bounded retry with backoff and
jitter, a circuit breaker, all inside the `Infrastructure` implementation, so Application never sees
Polly. By the time an exception reaches the consumer it means "FCM has been unreachable for the whole
configured window", not "one slow response" — the same reading `ChannelMessageDeliveryConsumer`
documents for itself, and the reason throwing at that point (into the DLQ) is right rather than
lossy.

**No per-send table.** `WebhookDelivery` and `ChannelDelivery` each write one row per delivery, and
this deliberately does not follow them: a push happens per *message*, so the table would grow with
traffic, and it would be a durable log of when each operator was notified about which conversation —
the same "growing store of who did what, when" shape `personal-data.md` already rejected when it
refused a deletion journal. What makes a broken device visible instead is bounded by device count:
`last_failure_at`/`failure_reason` on the row itself, plus the metrics below.

---

## Which hosts change

| Deployable | Change | Holds the FCM credential? |
|---|---|---|
| `Ago.Chat.Api` | One new endpoint group — `PUT`/`DELETE /api/v1/me/devices/{installationId}`, gated `RequireOperatorIdentity`. Writes a row. Never talks to FCM | **No** |
| `Ago.Chat.Worker` | Two consumers, one handler, one repository adapter, one FCM adapter; one extra call inside the existing `OperatorRemovedConsumer` | **Yes, and only here** |
| `Ago.Chat.Webhooks` | None | No |
| `ago-deploy` | One new key in `infra-credentials`, wired into the Worker deployment only | — |
| `ago-console` | **None.** The browser `Notification` path stays exactly as it is | — |
| `ago-android` | The client half — registration calls, `FirebaseMessagingService`, the notification channel, and `decideAlert`'s rule in Kotlin. `26-00`'s Settings screen depends on this design, not the reverse | — |

**No new host, and the reason is `adr/0013`'s own test: hosts split by failure profile, not by
domain.** Push fan-out's failure profile is "one third-party HTTP endpoint that may be slow or
unreachable, wrapped in a resilience policy" — which is precisely the profile `Ago.Chat.Worker`
already carries six times over, in the MAX, Telegram, VK, Avito, WhatsApp and Email adapters.
`Ago.Chat.Webhooks` was split out for a different reason that does not apply here: a *tenant's* own
endpoint, unbounded in latency and unbounded in number, where one tenant's bad endpoint must not
starve another's. FCM is one vendor, one endpoint, one policy. A seventh outbound integration in the
Worker is the boring answer and the right one.

**That the credential lives in exactly one deployable is itself a design choice.** Registration does
not need it, so `Ago.Chat.Api` — the only internet-facing host of the three — never holds it.

---

## The new secret

One new key in the `infra-credentials` Secret, per `secrets.md` section A: a **Google service-account
JSON** for the Firebase project, which the FCM v1 API requires in order to mint the OAuth2 bearer
token every send carries.

| | |
|---|---|
| **Name** | `FCM_SERVICE_ACCOUNT_JSON` |
| **Protects** | The ability to send a push to any device registered to this Firebase project |
| **Value lives** | `.env` on the deploying machine → `secretGenerator` → Secret. Never in any repository, never in a manifest, never in an `.env.example` beyond its shape |
| **Read by** | `Ago.Chat.Worker` only |
| **Rotation class** | **Restart** — and it can be made **Draining** at no cost, because a Google service account may hold more than one active key at a time: create the new key, swap the Secret, roll the Worker, then delete the old key. That ordering is the whole procedure |

It joins `secrets.md`'s table and `tools/secrets-audit.sh`'s allow-list in the same change that
introduces it, or the audit fails — which is the point of the audit.

Note what is **not** a secret and must not be treated as one: the FCM registration token on the
device row. It is a routing address, not a credential — closer to `ChannelIdentity`'s external
address than to `ChannelCredential`'s ciphertext. It is **not** encrypted at rest with
`CHANNELS_CREDENTIAL_ENCRYPTION_KEY`, and pretending otherwise would put a `Breaking`-class rotation
cost on a value that rotates on Google's schedule anyway.

---

## Quiet failure, and how it stops being quiet

Three ways this can fail silently, and what makes each visible.

**FCM is unreachable.** The adapter's retry and circuit breaker absorb the short version. The long
version throws, the consumer rethrows, and the message lands in `operator-assignment-push.dlq` /
`operator-message-push.dlq`. A non-empty DLQ is the signal, and it is the same signal
`ChannelMessageDeliveryConsumer` already relies on.

**A token is stale and FCM rejects it.** Terminal — the row is revoked, and the counter below records
it. Not a fault; it is the mechanism working.

**The consumer itself is broken or not running.** This is the dangerous one, because it looks exactly
like a quiet system. It is caught by a *pairing* rather than by any single number, and the first half
of the pair **already exists**: `ago.chat.delivery.recipients`, tagged `recipient_kind="operator"`
and `presence="absent"` (`7-08`, `adr/0044`) — an operator the fan-out had something for and could
not reach. That counter rising while the push counter stays at zero is push being dead, and it is a
condition no existing instrument can express on its own.

New instruments, in `ChatMetrics`, following the existing naming:

| Instrument | Kind | Tags |
|---|---|---|
| `ago.chat.push.sends` | Counter | `reason` (`assigned`/`message`), `provider`, `outcome` (`delivered` / `token_gone` / `failed`) |
| `ago.chat.push.suppressed` | Counter | `reason` — why the handler decided **not** to send (`no_devices`, `not_visitor`, `unassigned`). The number that distinguishes "push is broken" from "nobody has ever registered a device" |
| `ago.chat.push.tokens_revoked` | Counter | `cause` (`signed_out` / `provider_unregistered` / `operator_removed`) |

`ago.chat.push.suppressed{reason="no_devices"}` deserves its own line, because it is the failure this
whole feature is most likely to die of in practice: everything works, nobody registered, and every
other number looks healthy.

**A dashboard panel worth building, stated concretely:** one graph, three series — pushes delivered,
pushes failed, and `delivery.recipients{recipient_kind="operator",presence="absent"}`. The alert
condition is not a threshold on any one of them; it is *the third rising while the first is flat*.

Following `7-08`'s own restraint: **no alert is defined here**. `15-03` decides alert thresholds with
real data rather than with a guess made while adding the instrument, and this design does not break
that rule to feel thorough.

---

## Erasure, and what Google keeps

`site_id` carries an FK to `sites(id)` with `ON DELETE CASCADE`, so `SiteErasureQuery`'s own
`delete from sites where id = @siteId` takes the device rows with it — the same way it already takes
most of the schema, with only two explicit deletes of its own. **This must be verified against that
query at implementation rather than assumed**, because `adr/0168`'s own Consequences record exactly
this going wrong once already (`visitor_restrictions` needed an explicit delete, and `25-78` is the
item that says the cascade did not reach it).

**What Google keeps is not established, and that is a finding rather than a placeholder** — the same
answer `24-08` gives for every channel provider, for the same reason: it is Google's terms, not
derivable from these repositories. Erasing a site removes AGO's copy of a token and cannot remove
theirs.

`personal-data.md` gains a row in its *destinations outside this deployment* table, and
`processing-instruction-facts.md` gains a matching element. Two things make that row read differently
from every other row in it:

- **The subject is an operator, not a visitor.** `adr/0076` makes AGO the **controller** for its own
  account holders. So this transfer is AGO's own decision, made on its own basis — not something
  performed on a tenant's instruction, and not something a tenant switches on by storing a credential.
  Every existing row in that table is the opposite shape.
- **What crosses is small and deliberately so**: a device token, a title, a body naming a truncated
  pseudonymous visitor id, and a conversation id. **No message body, ever** — `alerts.ts`'s decision,
  carried over unchanged.

**Data residency.** `personal-data.md`'s standing constraint says the default answer for any new
destination is "in Russia", and moving one out "is a decision that must be made explicitly, in
writing, with the legal question asked first". FCM is a Google destination and there is no Russian
alternative that reaches a stock Android phone. This design states that plainly rather than routing
around it: **the legal question is the author's to ask, and it is a precondition on the
implementation item, not on this design.** The mitigation available regardless is minimisation, and
it is already taken: no body, no visitor identity beyond a truncated pseudonym, no conversation
content.

---

## Two measurements this design refuses to assume

This project does not invent numbers. Both of these are gates on the implementation item, in the same
way `14-05` gated the Telegram adapter on a real reachability spike before a line of it was written.

**1. Is `fcm.googleapis.com` reachable from the live node?** `adr/0070` measured
`api.telegram.org` from this same VPS and found 8 of 15 attempts never established TCP at all —
and it is the reason a VLESS relay is load-bearing for one channel today. Its **control run is
relevant evidence here and is not proof**: 5 of 5 requests to `https://www.google.com` succeeded from
the same VPS in the same window, 121–402 ms, on 2026-08-28. That is a different hostname, a different
Google service, and three weeks ago. The implementation item runs `adr/0070`'s own method — N
requests, spaced, fixed timeout, a deliberately invalid credential so an HTTP 401 proves a complete
round trip — against `fcm.googleapis.com` **and** `oauth2.googleapis.com`, since the token mint is a
second host and a second chance to fail. If either needs the relay, the adapter needs a proxy-aware
`HttpClient` wired in the composition root exactly as `TelegramProxyOptions` documents — a known
shape, not new work.

**2. Does the operator's own phone have Google Play Services?** FCM does not exist without it. On a
de-Googled ROM, or some devices sold in this deployment's own market, there is no backend design that
delivers a push — the product would need a second transport entirely. This is named as a product
risk, not solved here, because solving it is a different decision with a different cost and nobody
has yet established that any real operator is affected.

---

## The iOS/APNs boundary

The author intends a native iOS client after Android. `adr/0178` already refused to build a shared
mobile layer for a consumer that does not exist; the same rule applies to the backend, and the answer
here is narrower than it looks.

**What generalises, at zero cost:** the `provider` column, and `IPushSender` taking a `PushMessage`
rather than an FCM request. Neither is built *for* iOS. A `token` column with no `provider` beside it
is a column that lies about what it holds the moment a second kind of token exists, and a port whose
signature is an FCM payload would be a port with the adapter's vocabulary in it — a layering fault
today, independent of iOS. So the generalisation is a by-product of doing Android's own design
cleanly, which is the only kind this project accepts.

**What is deliberately not built:**

- **No APNs adapter.** No `Ago.Chat.Infrastructure.Apns` project, empty or otherwise — `adr/0178`
  already rejected creating `ago-mobile-common` empty as "the worst of both", and the same reasoning
  applies to an empty adapter.
- **No provider registry.** No `IReadOnlyDictionary<string, IPushSender>`, no strategy resolver, no
  `IPushSenderFactory`. One implementation is registered, directly. A dispatch table with one entry is
  a guess about the second, which is `clean-architecture.md`'s own rule and the ground `adr/0027`
  refused a hoisted `Operator` on.
- **No abstract notion of "notification content".** `PushMessage` carries what this product's one
  notification already is — a title, a body, a collapse key, a small data map — because
  `alertTextFor` already decided that shape for the web. It is not a guess at the intersection of two
  provider APIs; it is the thing being sent.

**The trigger that reopens it** is the first real iOS device registration. At that moment the
decision is whether `IPushSender` gains a second implementation selected by `provider`, or whether
APNs gets its own port because its payload and its error vocabulary turn out not to fit. That is
answerable then and not now, and the column being there means the question is a code change rather
than a migration.

---

## What this design deliberately leaves out

- **"A conversation is waiting" push.** There is no server-side signal (confirmed above), and the
  console does not alert on it either. Building one means a new integration event, a new broadcast to
  every operator of a site, and a new answer to "who gets told about an unassigned conversation" —
  three decisions this item was not scoped to make, and none of which `alerts.ts` has an opinion to
  reuse.
- **Team-chat mentions.** `TeamMessagePosted` exists and the console tracks unread team messages, but
  `useAlerts` is never called for one. Adding push here would be inventing a second rule set, which
  this design's own premise forbids.
- **Calendar bookings.** A different product, a different database, a different console
  (`adr/0027`).
- **Web Push for the console.** The console keeps the browser `Notification` API. Retiring that in
  favour of a service-worker Web Push path would let `ago-console` share this same fan-out, and it is
  a genuinely attractive future item — but it is a second client, a second provider vocabulary
  (VAPID), and a change to a working feature, none of which this item needs.
- **Per-operator quiet hours on the server.** The phone already has Do Not Disturb, and a server-side
  schedule would be a second, less capable copy of an OS feature — while introducing a timezone
  question (`date-and-time.md`) for a rule nobody has asked for.

## Implementation items this design implies

Named so the split is on promises rather than on code, per rule 15. Each lands green on its own.

1. **Device registration.** `operator_devices` + `OperatorDevice` + `IOperatorDeviceRepository` +
   the two `Api` routes + the migration. Ends green with a registered, refreshed and revoked device,
   and nothing sending anything. **This is the migration-lane item.**
2. **The FCM adapter.** `Ago.Chat.Infrastructure.Fcm`, `IPushSender`, the credential, the resilience
   policy. Gated on measurement 1 above. Ends green with a send proven against the real service.
3. **The fan-out.** Two consumers, `NotifyOperatorDevicesHandler`, the metrics, the
   `OperatorRemovedConsumer` addition. Ends green with a real phone buzzing.
4. **The Android client half.** `ago-android` — registration calls, `FirebaseMessagingService`,
   `decideAlert` in Kotlin, the notification channel, `26-00`'s Settings screen made honest.

Items 1 and 2 are independent of each other; 3 needs both; 4 needs 1 and can be written against 3 in
parallel.
