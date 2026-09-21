# Push notifications to an operator's phone

> **Status: designed, not built.** `26-01`, 2026-09-21. Every mechanism on this page is a design.
> Nothing here exists in `Ago.Chat.*` today — no table, no port, no consumer, no credential. The
> paragraph *[What is true today](#what-is-true-today)* is the only part of this file that describes
> running code, and it says that the only way an operator learns anything is a live SignalR
> connection. Read the rest as intent, the way `docs/backlog/` is read. The decisions behind it are
> [`adr/0179`](../adr/0179-operator-push-is-a-worker-fan-out-to-a-device-row-and-the-loudness-decision-stays-on-the-client.md)
> and [`adr/0180`](../adr/0180-operator-push-goes-through-rustore-push-not-fcm.md).
>
> **The provider changed on 2026-09-21, before a line of it was written.** `adr/0179` designed this
> against Firebase Cloud Messaging; `adr/0180` partially supersedes it and the provider is now
> **RuStore Push**, for `personal-data.md`'s data-residency default. Most of `adr/0179` stands - the
> table, the consumers, the rule that the client decides loudness, the absence of a new host. What
> this page carries below is the RuStore version throughout; where the provider's own documentation
> does not answer something, it says so rather than filling the gap in.
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
returns nothing outside a Razor build cache and two compressed git objects; `rustore` returns nothing
at all, which is unsurprising for a provider chosen the same day. `ago-platform` is not
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
| A conversation entered the **waiting queue** | **Nothing.** There is no `ConversationStarted` contract and no mapper for one. `realtime.md` states it in so many words: "nothing broadcasts 'a new conversation started waiting' to every operator of a site (only the operator it eventually gets assigned to ever hears about it)" — the console's own waiting list is a 15-second poll (`WorkspaceLayout.tsx`'s own `WAITING_REFRESH_INTERVAL_MS`) | **No signal exists**, and the console does not alert on this either. Out of scope, see [What this design deliberately leaves out](#what-this-design-deliberately-leaves-out) |
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
                                        Ago.Chat.Infrastructure.RuStore
                                                   |
                                                   v
                                        vkpns.rustore.ru
                                                   |
                                                   v
                              the distributor app on the phone (RuStore)
                                                   |
                                                   v
                                        RuStoreMessagingService  ->  the app
```

**That last hop is not decoration, and it is the biggest difference from FCM.** RuStore Push has no
transport of its own on the device: a *distributor* app - RuStore, or an undisclosed VK fallback
elected remotely - polls the server and forwards what it finds to apps embedding the SDK. See
[Delivery is a distributor, not a socket](#delivery-is-a-distributor-not-a-socket).

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
| `site_id` | `uuid not null`, FK → `sites(id)` | Tenant scope is a fact on the row, not a join. Also what makes site erasure cascade for free (see [Erasure](#erasure-and-what-the-provider-keeps)) |
| `operator_id` | `uuid not null`, FK → `operators(id)` | The fan-out's own lookup key — `ConversationAssignedToOperator` already carries exactly this |
| `installation_id` | `text not null` | The client-generated, stable-per-install identifier. **This, with `operator_id`, is the row's identity** |
| `provider` | `text not null` | `'rustore'` today. It was going to be `'fcm'` until `adr/0180`, which is the column's first piece of evidence for itself. See [The iOS boundary](#the-iosapns-boundary) |
| `platform` | `text not null` | `'android'` today — diagnostic, not routing |
| `token` | `text not null` | The RuStore push token. A **value on** the row, replaced in place on every refresh |
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

Push tokens are **not stable**, under either provider. RuStore's own SDK release history is the
evidence: versions 6.8.0 and 6.9.1 each changed the reissue logic so that tokens are reissued *less*
often, which is a statement that they are reissued. A design that treats a token as an identifier
accumulates one dead row per rotation, for ever.

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

The Android client calls it in three places, and all three matter: **on every sign-in** (the token
itself from `RuStorePushClient.getToken()`, which mints one if none exists), **from
`RuStoreMessagingService.onNewToken`** — the provider's own rotation callback, and the only event
that can tell the app its token changed — and **on a schedule the app itself sets** (a `WorkManager`
job, because `onNewToken` cannot fire for an app that was not running when the rotation happened).
The third one is what turns `last_seen_at` into a usable liveness signal rather than a record of the
last sign-in.

The callback's name and shape are the same ones this design was written against under FCM, which is
why `adr/0180` changed nothing here: RuStore's is `onNewToken(token: String)` on a service extending
`RuStoreMessagingService`, and its documentation says in so many words that after it fires *the app
is responsible for delivering the new token to its own server*.

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

**The provider says the token is gone.** RuStore's send API answers with a body carrying `code`,
`message` and `status`, the HTTP status matching `code`. Two outcomes are terminal, and exactly two:

| Outcome | HTTP | `status` | Treatment |
|---|---|---|---|
| Malformed push token | `400` | `INVALID_ARGUMENT` | **Terminal** — revoke the row |
| Valid token that has expired | `404` | `NOT_FOUND` | **Terminal** — revoke the row |
| Bad service key | `403` | `PERMISSION_DENIED` | **Never** a device fault. This is *our* credential, and treating it as one would revoke every device in the table the first time the token was rotated wrong |
| Rate limited | `429` | `TOO_MANY_REQUESTS` | Transient — back off, record `last_failure_at` |
| Service error | `500` | `INTERNAL` | Transient |

The sender reports the outcome and the handler calls
`IOperatorDeviceRepository.RevokeByTokenAsync(provider, token, reason)`. **This is the mechanism that
actually keeps the table clean**, and it is the reason the table needs no sweep job: the provider
tells us, on the next send, and we believe it.

**The adapter keys on `status` and `code`, never on `message`.** RuStore's own published example of a
malformed-token response carries the text *"The registration token is not a valid FCM registration
token"* — a Firebase string surviving inside a RuStore error body, which is consistent with RuStore
describing the API as a drop-in replacement for Firebase, and is a good reason to trust the field
with a documented enumeration over the one that is prose.

*Two documented gaps, named rather than papered over.* The `status` field's own description lists
`UNREGISTERED` among its example values while the page's enumerated error list does not include it —
so treat `UNREGISTERED` as terminal if it ever arrives, but do not depend on it. And **no numeric
rate limit is published**: `TOO_MANY_REQUESTS` exists, its threshold does not, so this design makes
no throughput claim.

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
phone makes the argument stronger, not weaker. What goes to RuStore is a title, a body naming the
visitor's eight-character pseudonymous id, and the conversation id — carried in `message.data`, for
the reason the next section gives.

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
makes the answer honest rather than merely convenient. Messages are sent as **data-only messages,
never `notification` payloads.** A `notification` payload is rendered *by the RuStore SDK itself*
with no app code consulted; a data message wakes `RuStoreMessagingService.onMessageReceived`, and the
app decides. So the app applies the identical rule the console applies — *is this conversation open
on this screen, and is this screen actually in front of the user?* — and stays silent when it is.
`decideAlert`'s logic is reused, not duplicated: it simply runs on each client, which is where
`alerts.ts` put it in the first place.

The rule, stated once: **the server decides who is told; each client decides whether to be loud.**

**This was the load-bearing check when the provider changed**, because the whole answer above is
unimplementable if the app cannot receive a message without the system drawing it first. RuStore
supports it and says so on both halves. Client side, from the SDK's `onMessageReceived`
documentation: if the `notification` object carries data the SDK displays the notification itself, so
to prevent that, use the `data` object and leave `notification` empty — and the method is called
*"in any case"*. Server side, from the send API's own validation algorithm: a message whose `data` is
present and non-empty is valid with `message.notification` and `message.android` omitted entirely.

**One ambiguity in that validation rule is named and not guessed at.** It is written as *"if
`message.data.payload` is present and non-empty"* while `message.data` is typed in the same document
as a flat `map[string]string`. Whether a data-only message must carry a key literally named
`payload`, or whether that is loose wording for the map itself, is not answerable from the
documentation. **`26-04`'s first real send settles it**; nothing here assumes either reading.

Costs of data-only messages, all real, and **the first is not the one FCM had**:

- **There is no priority lever at all.** `adr/0179` accepted `android: { priority: "high" }` as the
  price of escaping Doze, set for these two message kinds only because Google throttles overuse.
  RuStore's documented send schema has **no `priority` field** — the page says only the listed fields
  are supported — and on the client, `RemoteMessage.priority` is documented as *not currently taken
  into account*. So there is nothing to set, nothing to be throttled for, and no documented way to
  ask for prompt delivery. That argument is deleted rather than translated, and what replaces it is
  the next section.
- If the app is force-stopped by the user, no data message reaches it at all. That is Android's rule,
  not a design choice, and no payload shape changes it.
- The service has **20 seconds** to finish handling a message before the system may kill it
  (RuStore's own warning; 6.2.1 made the shutdown deterministic). Rendering a notification is well
  inside that; a network round trip on the receive path would not be, which is one more reason the
  payload carries what the notification needs rather than an id to go and fetch.

### Delivery is a distributor, not a socket

The single largest difference between the two providers, and a reader must not miss it.

RuStore Push has **no transport of its own on the device**. Its documentation opens by describing
the mechanism: a *distributor* application must be installed; it periodically asks the server whether
anything is waiting for apps that embed the SDK, and forwards what it finds to them. RuStore is the
primary distributor. Where it is absent, *one of the other VK applications* may take the role — the
choice is made **remotely, on the server**, RuStore explicitly declines to publish the list of
possible fallbacks, and it notes that the set can change and that the elected app on a given device
may differ at any moment. Only one acts as distributor at a time; the rest sleep, and a replacement
is elected automatically if the current one is removed or its settings change.

Two things follow, and both are load-bearing:

- **This design makes no latency claim whatsoever.** No polling interval is published, no
  delivery-time target, and per the section above no priority lever exists. Rule 7 forbids inventing
  a number; `26-04`/`26-18` measure it. Until then, *"the phone buzzes while it is in a pocket"* is
  the promise and the latency at which it does so is unknown.
- **A device with RuStore installed but denied background permission still receives pushes** —
  RuStore's own words, *"но со значительной задержкой"*, with significant delay. That is a per-device
  setting nothing on the server can observe or correct, surfaced to the app as
  `HostAppBackgroundWorkPermissionNotGranted`.

### What the operator's phone has to satisfy

`adr/0179` named one client-side prerequisite — Google Play Services — as a product risk it did not
solve. RuStore publishes a longer list, and it is **the finding most likely to change the provider
decision**, so it is stated here in full rather than in a footnote:

1. A **distributor app is installed** (RuStore, or an undisclosed fallback). The documented check is
   `RuStorePushClient.checkPushAvailability()`, returning `FeatureAvailabilityResult.Available` or
   `Unavailable(cause)`; an absent distributor surfaces as `HostAppNotInstalledException`.
2. If RuStore is installed, it is **allowed to run in the background** — otherwise the delay above.
3. The **operator is authorized in RuStore**, i.e. holds and is signed in to a RuStore account —
   a second identity this product neither controls nor can provision. Surfaced as
   `UnauthorizedException`, with the documented caveat that it may not be raised even when the user
   *is* unauthorized, because the behaviour is controlled dynamically in the SDK. Handle it; do not
   rely on it.
4. The **signature fingerprint** of the installed build matches the one registered under Push
   notifications → Projects in RuStore Console. Debug and release signatures and package names
   differ, so RuStore requires **a separate console project per build type** — a real development
   chore, not a deployment detail.
5. App data uploaded in that console section, and a current SDK version in use.

**Read against FCM this is a harder product question, not an easier one.** Play Services is present
on most stock phones with no user action and no second account; a RuStore distributor, signed in and
un-restricted, is not. The trade was made for data residency (`adr/0180`) with that cost named. What
*is* strictly better than the FCM design had is that the condition is now programmatically checkable
on the device, where "does this phone have Play Services" was named with no API beside it.

**Not established, and it matters for how the app is distributed:** whether push works for an app
registered in the console but never published through RuStore. The condition list asks for uploaded
app data and a matching fingerprint, not for a published listing — but it does not say the two are
independent, and RuStore's documentation does not answer it. `26-06` finds out.

### Idempotency, without an inbox row

Rule 5 says consumers are idempotent; at-least-once means a redelivered `MessageAccepted` would reach
this consumer twice.

**No `inbox` ledger.** `adr/0020` already permits this for "a purely derived, best-effort
notification computed from an already-outboxed event", which is exactly what a push is. That refusal
survived the provider change; the mechanism underneath it did not, and the difference is worth being
precise about.

**There is no collapse key on the wire.** `adr/0179` rested half of this on an FCM collapse key
`ago-conversation-{conversationId}`. RuStore's send schema has **no `collapse_key` field** — the
reference says only the listed fields are supported — and on the client, `RemoteMessage.collapseKey`
is documented as *not currently taken into account*. So that half does not exist here.

What idempotency actually rests on, both halves client-side:

- **The notification tag `ago-conversation-{conversationId}`**, the identical value `useAlerts.ts`
  already uses as its `Notification` `tag`, for the identical reason ("a visitor sending four
  messages replaces its own card rather than stacking four"). **This is the half that was always
  doing the work**, and it survives intact *because* the design already renders the notification in
  app code rather than letting the SDK draw it: the client calls `NotificationManagerCompat.notify`
  with that tag and Android's notification manager collapses delivered notifications by it.
- **Client-side dedupe by `MessageId`**, which the data payload carries — the same
  dedupe-by-message-id the widget already does for redelivered broker messages (`messaging.md`).
  `RemoteMessage.messageId` also exists as a provider-assigned id, so there is a second field
  available if the payload's own ever proves insufficient.

That is idempotent *in effect*, which is what rule 5 asks for. An `inbox` row per push would add a
database write to every notification to prevent a duplicate the tag already collapses.

*What is genuinely lost with the collapse key*, stated so nobody meets it as a surprise: FCM
additionally collapsed **undelivered** messages queued for a phone that was offline. RuStore does
not. A phone off the network for a while and then reconnecting may receive several queued pushes for
one conversation and collapse them into one card *on arrival*, rather than having been sent one.
Same card at the end, more radio traffic and more `onMessageReceived` calls to get there.

*The honest limit, unchanged:* a redelivery separated by more than the user's own dismissal will buzz
twice. It is a buzz, not a corrupted counter, and `RecordUnreadMessageHandler` — which does maintain
real state — keeps its `IInboxChecker` row exactly as it has since `2-05`.

### `ttl` is a real decision, because the default is four weeks

RuStore stores an undelivered message for **four weeks** when `ttl` is absent or zero — and if
`message.android` is missing entirely, the documentation says it is added with the `ttl` field. A
notification saying a visitor is waiting is worthless long after the fact; delivered four weeks later
it is noise that costs an operator their trust in the whole feature, and `onDeletedMessages` below is
the better answer for a phone that was away.

So **`android.ttl` is set explicitly on every send, and short.** The number is not chosen here,
because this project does not invent numbers: `26-04` picks it, states the reasoning and records it.
What is decided here is that leaving it unset is wrong. (Maximum message size is 4096 bytes, which
`alertTextFor`'s deliberately body-free text is nowhere near.)

### Ordering

Rule 6 guarantees order per conversation and never globally, and this path needs neither. A push says
"something new happened in conversation X", never "here is message 7" — there is no sequence to get
wrong, and the notification tag deliberately makes the *latest* push the surviving card, which is the
correct semantic for a notification. That property now lives entirely on the client, since RuStore
carries no collapse key — which changes where it is implemented, not whether it holds.

---

## The port, and what crosses it

```
Ago.Chat.Application/Abstractions
    IOperatorDeviceRepository      Upsert / Revoke / RevokeByToken / ListActiveForOperator
    IPushSender                    Task<PushSendOutcome> SendAsync(PushMessage, CancellationToken)
    PushMessage                    (DeviceToken, Title, Body, GroupKey, TimeToLive, Data)
    PushSendOutcome                Delivered | TokenGone(reason) | TransientFailure(reason)

Ago.Chat.Infrastructure.Postgres   OperatorDeviceRepository        (EF Core — a write store)
Ago.Chat.Infrastructure.RuStore    RuStorePushSender               (HTTP, bearer token, resilience)
```

`PushMessage` keeps a grouping value even though RuStore does not collapse on one, because the
*client* does (see [Idempotency](#idempotency-without-an-inbox-row)) and the payload is how it gets
there — it travels in `data`, not as a provider field. `TimeToLive` is new, for the reason the
section above gives.

*Why a port at all, stated for the teaching record:* rule 2 — the push provider is an external
resource, so `HttpClient` may not appear in Application, and the handler must be testable with a fake
that returns `TokenGone` without a network. The alternative, calling a provider SDK from the handler,
would make the revocation-on-terminal-error rule — the one rule that keeps the table from rotting —
untestable without the real service.

*And the port had to hold a real weight one day after it was designed.* `adr/0179` argued that
`IPushSender` taking a `PushMessage` rather than a provider request shape was a by-product of correct
layering, not preparation for a second provider. `adr/0180` changed the provider before a line of
adapter code existed: the port's signature did not move, and neither did `provider` as a column. That
is the cheapest possible evidence that the judgement was right, and it is worth recording because the
opposite outcome — a port shaped like FCM's request — would have meant rewriting the Application
layer for a decision made entirely outside it.

*Why `IOperatorDeviceRepository` is EF and not a Dapper read store:* the fan-out both **reads**
tokens and **writes** revocations, in the same flow, for a row with an invariant
(`adr/0004` puts writes behind EF). A separate Dapper read store for a handful of rows keyed by one
indexed column would be a second port for the same table with no query it can express better —
the same judgement `ListMyTenanciesHandler` already records for its own small read.

*Why the resilience lives in the adapter:* `resilience.md`'s established shape and
`IWebhookDeliveryClient`'s own remarks — per-endpoint timeouts, bounded retry with backoff and
jitter, a circuit breaker, all inside the `Infrastructure` implementation, so Application never sees
Polly. By the time an exception reaches the consumer it means "`vkpns.rustore.ru` has been
unreachable for the whole configured window", not "one slow response" — the same reading
`ChannelMessageDeliveryConsumer` documents for itself, and the reason throwing at that point (into
the DLQ) is right rather than lossy. `429 TOO_MANY_REQUESTS` is part of what that policy absorbs, and
it has to be handled on judgement rather than on a published figure: **RuStore documents the error
and not its threshold.**

**No per-send table.** `WebhookDelivery` and `ChannelDelivery` each write one row per delivery, and
this deliberately does not follow them: a push happens per *message*, so the table would grow with
traffic, and it would be a durable log of when each operator was notified about which conversation —
the same "growing store of who did what, when" shape `personal-data.md` already rejected when it
refused a deletion journal. What makes a broken device visible instead is bounded by device count:
`last_failure_at`/`failure_reason` on the row itself, plus the metrics below.

---

## Which hosts change

| Deployable | Change | Holds the push credential? |
|---|---|---|
| `Ago.Chat.Api` | One new endpoint group — `PUT`/`DELETE /api/v1/me/devices/{installationId}`, gated `RequireOperatorIdentity`. Writes a row. Never talks to the provider | **No** |
| `Ago.Chat.Worker` | Two consumers, one handler, one repository adapter, one RuStore adapter; one extra call inside the existing `OperatorRemovedConsumer` | **Yes, and only here** |
| `Ago.Chat.Webhooks` | None | No |
| `ago-deploy` | One new key in `infra-credentials`, wired into the Worker deployment only | — |
| `ago-console` | **None.** The browser `Notification` path stays exactly as it is | — |
| `ago-android` | The client half — registration calls, a `RuStoreMessagingService`, the notification channel, and `decideAlert`'s rule in Kotlin. `26-00`'s Settings screen depends on this design, not the reverse | — |

**No new host, and the reason is `adr/0013`'s own test: hosts split by failure profile, not by
domain.** Push fan-out's failure profile is "one third-party HTTP endpoint that may be slow or
unreachable, wrapped in a resilience policy" — which is precisely the profile `Ago.Chat.Worker`
already carries six times over, in the MAX, Telegram, VK, Avito, WhatsApp and Email adapters.
`Ago.Chat.Webhooks` was split out for a different reason that does not apply here: a *tenant's* own
endpoint, unbounded in latency and unbounded in number, where one tenant's bad endpoint must not
starve another's. RuStore Push is one vendor, one endpoint, one policy — more literally so than FCM,
which needed a second host to mint a token. A seventh outbound integration in the Worker is the
boring answer and the right one.

**That the credential lives in exactly one deployable is itself a design choice.** Registration does
not need it, so `Ago.Chat.Api` — the only internet-facing host of the three — never holds it.

---

## The new secret

One new key in the `infra-credentials` Secret, per `secrets.md` section A: the **RuStore service
token**, presented directly as `Authorization: Bearer {service-token}` on every send. There is no
OAuth2 mint and therefore no key file, no second host and no token cache — which is the one place the
provider change made the design strictly simpler.

| | |
|---|---|
| **Name** | `RUSTORE_PUSH_SERVICE_TOKEN` |
| **Protects** | The ability to send a push to any device registered to this RuStore push project |
| **Value lives** | `.env` on the deploying machine → `secretGenerator` → Secret. Never in any repository, never in a manifest, never in an `.env.example` beyond its shape |
| **Read by** | `Ago.Chat.Worker` only |
| **Rotation class** | **Restart.** `adr/0179` could promise *Draining* for free because a Google service account may hold two active keys at once. **RuStore's documentation does not say whether a push project can hold two live service tokens, or whether issuing one invalidates the other** — so the weaker class is recorded and the better one is not claimed. Whoever first opens the console finds out; `26-04` records the answer |

It joins `secrets.md`'s table and `tools/secrets-audit.sh`'s allow-list in the same change that
introduces it, or the audit fails — which is the point of the audit.

**The project ID is not a secret and must not be treated as one.** It ships inside the app's own
`AndroidManifest.xml` as `ru.rustore.sdk.pushclient.project_id`, so it is readable from any copy of
the APK and no amount of server-side care changes that. It is still supplied as deploy-time
configuration alongside the token rather than committed, on the ordinary ground that these
repositories are public and a deployment identifier belongs in `.env` with its neighbours — but it
does not get a secrets-rotation class, because calling something a secret when its value is in every
installed app is the kind of claim that makes the rest of `secrets.md` less trustworthy.

Note what is **also not** a secret: the push token on the device row. It is a routing address, not a
credential — closer to `ChannelIdentity`'s external address than to `ChannelCredential`'s ciphertext.
It is **not** encrypted at rest with `CHANNELS_CREDENTIAL_ENCRYPTION_KEY`, and pretending otherwise
would put a `Breaking`-class rotation cost on a value that rotates on the provider's schedule anyway.

---

## Quiet failure, and how it stops being quiet

Three ways this can fail silently, and what makes each visible.

**The provider is unreachable.** The adapter's retry and circuit breaker absorb the short version. The long
version throws, the consumer rethrows, and the message lands in `operator-assignment-push.dlq` /
`operator-message-push.dlq`. A non-empty DLQ is the signal, and it is the same signal
`ChannelMessageDeliveryConsumer` already relies on.

**A token is stale and the provider rejects it.** Terminal — the row is revoked, and the counter below records
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

## Erasure, and what the provider keeps

`site_id` carries an FK to `sites(id)` with `ON DELETE CASCADE`, so `SiteErasureQuery`'s own
`delete from sites where id = @siteId` takes the device rows with it — the same way it already takes
most of the schema, with only two explicit deletes of its own. **This must be verified against that
query at implementation rather than assumed**, because `adr/0168`'s own Consequences record exactly
this going wrong once already (`visitor_restrictions` needed an explicit delete, and `25-78` is the
item that says the cascade did not reach it).

**What RuStore keeps is not established, and that is a finding rather than a placeholder** — the same
answer `24-08` gives for every channel provider, for the same reason: it is the provider's terms, not
derivable from these repositories. Erasing a site removes AGO's copy of a token and cannot remove
theirs. The client can ask for its own token to be dropped (`RuStorePushClient.deleteToken()`), which
is an affordance FCM's design did not name and `26-06` should use on sign-out alongside the
`DELETE` call — but it is the *device* discarding its token, not a statement about what the server
retains.

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

- **The delivery path has one more named-but-unnamed hop than FCM's, and the row should say so.**
  Under FCM the payload crossed Google's servers and then Google Play Services — one vendor, one
  system component. Under RuStore it crosses RuStore's servers and then **whichever distributor app
  is currently elected on that operator's own device**, which RuStore declines to enumerate and says
  may change. Every hop is domestic, and the path is still wider and less named than FCM's. Writing
  the row honestly means writing that, not just the country.

**Data residency — settled, and here is exactly how.** `personal-data.md`'s standing constraint says
the default answer for any new destination is "in Russia", and that moving one out "is a decision
that must be made explicitly, in writing, with the legal question asked first". **RuStore Push is
Russian infrastructure, so the default is satisfied on its own terms and no written escalation is
needed at all** (`adr/0180`). The author reached that by changing the destination rather than by
answering the legal question — a choice not to have to ask it.

Two things keep that from being told as a bigger win than it is. **No claim is made that this is more
private than FCM**; it is closer, under a domestic legal regime, which is what the constraint asks
for and nothing more. And the decision was taken when it cost nothing: **zero real tenants, not one
operator token in any table, and no adapter written** — so it is the cheap option taken while it was
still cheap, not a response to an exposure. The price is real and is named throughout this page: an
unmeasurable latency, a longer prerequisite list, and a thinner manual.

The mitigation is unchanged and still taken regardless: no body, no visitor identity beyond a
truncated pseudonym, no conversation content.

---

## Four measurements this design refuses to assume

This project does not invent numbers. All four are gates on the implementation items, in the same way
`14-05` gated the Telegram adapter on a real reachability spike before a line of it was written.
`adr/0179` named two; the provider change removed one, split another, and added the one this page
cares about most.

**1. Is `vkpns.rustore.ru` reachable from the live node?** `adr/0070` measured `api.telegram.org`
from this same VPS and found 8 of 15 attempts never established TCP at all — it is the reason a VLESS
relay is load-bearing for one channel today. The implementation item runs that same method — N
requests, spaced, fixed timeout, **a deliberately invalid service token so an HTTP 403
`PERMISSION_DENIED` proves a complete round trip** (RuStore's own documented code for a bad service
key; `adr/0179` used FCM's 401 for the same purpose). **One host, not two** — there is no OAuth2 mint
to reach a second. If a relay turns out to be needed, the adapter takes a proxy-aware `HttpClient`
wired in the composition root exactly as `TelegramProxyOptions` documents — a known shape, not new
work.

`adr/0070`'s control run is **less relevant here than it was for FCM, not more**, and saying so is
the same discipline that ADR applied to itself: it measured `https://www.google.com` from this VPS on
2026-08-28. A Russian host reached from a VPS in Russia is a different question, and that data says
nothing about it.

**2. Is `nexus-external.rustore.ru` reachable from CI?** New, and build-time rather than runtime.
`ago-android`'s CI has never fetched from a RuStore Maven repository, and a green local build proves
nothing about a GitHub Actions runner. Smaller risk than a runtime dependency, not zero. Only the
`nexus-external` address is used: RuStore's own docs say the older
`artifactory-external.vkpartner.ru` address *"may stop working at some point"*. (A third-party issue
tracker names 2026-10-01 for that retirement. **Secondary, unverified, and not relied on** — the
reason to use the new address is RuStore's own sentence, not that date.)

**3. What is the actual delivery latency?** The one this page most wants answered, and the one that
did not exist under FCM, where a priority flag and a documented Doze story stood in for it. RuStore
publishes **no polling interval, no delivery-time target, and no priority lever**
([Delivery is a distributor](#delivery-is-a-distributor-not-a-socket)). The product's whole promise
is that the phone buzzes while it is in a pocket, so `26-18` measures wall-clock time from send to
notification on a real phone — screen off, and again with RuStore's background permission denied,
since RuStore's own documentation says the second case is significantly slower without saying by how
much. **No number is asserted anywhere on this page until that runs.**

**4. Does `checkPushAvailability()` return `Available` on the operator's own phone?** This replaces
`adr/0179`'s "does the phone have Google Play Services", and it is a better-shaped question because
it is an API call rather than something somebody has to eyeball —
`RuStorePushClient.checkPushAvailability()`, with `HostAppNotInstalledException` as the documented
cause when no distributor is present. It is still a **product risk, not solved here**: the full
condition list is in [What the operator's phone has to satisfy](#what-the-operators-phone-has-to-satisfy),
it is longer than FCM's, and one of its items is that the operator holds a RuStore account. `26-18`
reports what it finds rather than assuming the happy case.

---

## The iOS/APNs boundary

The author intends a native iOS client after Android. `adr/0178` already refused to build a shared
mobile layer for a consumer that does not exist; the same rule applies to the backend, and the answer
here is narrower than it looks.

**What generalises, at zero cost:** the `provider` column, and `IPushSender` taking a `PushMessage`
rather than a provider request. Neither is built *for* iOS. A `token` column with no `provider`
beside it is a column that lies about what it holds the moment a second kind of token exists, and a
port whose signature is one vendor's payload would be a port with the adapter's vocabulary in it — a
layering fault today, independent of iOS. So the generalisation is a by-product of doing Android's
own design cleanly, which is the only kind this project accepts.

**Both of those were vindicated one day later, by an event that had nothing to do with iOS.**
`adr/0180` changed the provider from FCM to RuStore Push before a line of adapter code existed. The
column absorbed it, the port's signature did not move, and no Application-layer type changed. The
second provider that justified them turned out to be the first one.

**One RuStore-specific option is deliberately declined here and named as the reopening point.**
RuStore also publishes a *Universal* push API (`POST https://vkpns-universal.rustore.ru/v1/send`)
that fans a single request out through RuStore, FCM, HMS and APNS. It is genuinely attractive from
where this section stands: it would be one API for the iOS client, and it would let a phone with no
distributor fall back to FCM — the direct answer to the prerequisite problem above, which is this
design's worst consequence. It is rejected for the reason `adr/0180` exists: reaching FCM whenever
RuStore is unavailable puts the Google destination back, conditionally and far less visibly. It is
also worse operationally for that same goal — RuStore's documentation says each provider's own
credentials travel **in the request body** and that RuStore does not store them, so `Ago.Chat.Worker`
would be holding a Google service account after all. If measurement 3 or 4 above comes back badly,
this is the first thing to reconsider, with the residency question then asked properly rather than
routed around.

**What is deliberately not built:**

- **No APNs adapter.** No `Ago.Chat.Infrastructure.Apns` project, empty or otherwise — `adr/0178`
  already rejected creating `ago-mobile-common` empty as "the worst of both", and the same reasoning
  applies to an empty adapter.
- **No provider registry.** No `IReadOnlyDictionary<string, IPushSender>`, no strategy resolver, no
  `IPushSenderFactory`. One implementation is registered, directly. A dispatch table with one entry is
  a guess about the second, which is `clean-architecture.md`'s own rule and the ground `adr/0027`
  refused a hoisted `Operator` on.
- **No abstract notion of "notification content".** `PushMessage` carries what this product's one
  notification already is — a title, a body, a grouping key, a time-to-live, a small data map —
  because `alertTextFor` already decided that shape for the web. It is not a guess at the
  intersection of two provider APIs; it is the thing being sent.

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
2. **The RuStore Push adapter** (`26-04`). `Ago.Chat.Infrastructure.RuStore`, `IPushSender`, the
   service token, the resilience policy, the explicit `ttl`. Gated on measurement 1 above. Ends green
   with a send proven against the real service.
3. **The fan-out** (`26-05`). Two consumers, `NotifyOperatorDevicesHandler`, the metrics, the
   `OperatorRemovedConsumer` addition. Ends green with a real phone buzzing.
4. **The Android client half**, split on promises into `26-06` (the server knows about this device)
   and `26-18` (the phone buzzes correctly) — registration calls, a `RuStoreMessagingService`,
   `decideAlert` in Kotlin, the notification channel, `26-00`'s Settings screen made honest.

Items 1 and 2 are independent of each other; 3 needs both; 4 needs 1 and can be written against 3 in
parallel.

---

## The client SDK, by its real names

Read from RuStore's own Kotlin/Java Push SDK documentation on 2026-09-21, so `26-06` and `26-18` do
not have to guess at a plausible-sounding API.

| | |
|---|---|
| Maven repository | `https://nexus-external.rustore.ru/repository/maven-rustore-exposed/` |
| Dependency | `ru.rustore.sdk:pushclient` — **7.4.0** is the newest in the published release history as of 2026-09-21 |
| Minimum Kotlin | 1.8 |
| Credentials file | **None.** There is no `google-services.json` equivalent — initialisation takes a project-ID string and nothing else |
| Initialisation | `RuStorePushClient.init(application, projectId, logger)`, or automatically via the `ru.rustore.sdk.pushclient.project_id` manifest meta-data. **Not multi-process safe** — initialise in the main process only |
| Receiver | A service extending `RuStoreMessagingService`, declared with `android:exported="true"` and an intent filter on `ru.rustore.sdk.pushclient.MESSAGING_EVENT` |
| Callbacks | `onNewToken(token)`, `onMessageReceived(message: RemoteMessage)`, `onDeletedMessages()`, `onError(errors)` — all on a background thread, all subject to the 20-second limit |
| Token | `RuStorePushClient.getToken()` (mints one if absent), `deleteToken()` |
| Availability | `RuStorePushClient.checkPushAvailability()` → `Available` / `Unavailable(cause)` |
| Payload | `RemoteMessage(messageId, priority, ttl, from, collapseKey, data, rawData, notification)`. `priority` and `collapseKey` are both documented as **not currently taken into account** |
| Notification permission | `POST_NOTIFICATIONS` is in the SDK's own manifest from 1.4.0; the app must still request it at runtime on Android 13+ |
| Errors | `UnauthorizedException`, `HostAppNotInstalledException`, `HostAppBackgroundWorkPermissionNotGranted` — all deriving from `RuStorePushClientException` |
| Test mode | `testModeEnabled = true` plus `sendTestNotification(...)`. **It does not touch the backend at all** and mints a test token, so it proves client wiring and nothing about the real path |

**`onDeletedMessages()` is an affordance the FCM design never named**, and it is worth using: RuStore
calls it when one or more pushes were not delivered — TTL expiry being the example it gives — and
recommends syncing with your own server so data is not missed. Given the short `ttl` this design now
sets, that callback is the correct recovery hook for a phone that was away, and `26-18` wires it to
the refresh the conversation list already has.
