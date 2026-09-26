# ADR-0179: Operator push is a Worker fan-out to a device row, and the loudness decision stays on the client

- **Status**: Accepted; **partially superseded by ADR-0180** (2026-09-21) - the provider is RuStore
  Push, not FCM, and everything downstream of that choice is replaced: the credential (§4), the
  collapse key (§2), the `priority = "high"` mechanic (§3), the adapter project (§5) and both of §6's
  measurements. **What stands is most of it** - the `operator_devices` schema and its revocation
  rules (§1), the two-consumer fan-out and the reuse of `alerts.ts`'s rules (§2), the decision that
  the server never suppresses on presence and the client decides loudness (§3), the no-new-host
  ruling (§4), and the `provider`-column/`PushMessage`-port judgement (§5), which `adr/0180` is the
  first evidence for. The body below is unchanged - not one line - because this directory's own rule
  is that a `Status` pointer is the only edit an accepted ADR may receive, and an amendment in the
  body is what makes a file look current while carrying its own reversal several screens down.
- **Amended by ADR-0181** (2026-09-24): FCM returns as the *primary* transport with RuStore kept as the
  fallback. This restores this ADR's original FCM provider choice and its `FCM_SERVICE_ACCOUNT_JSON`
  credential (§4) as one of two transports, and is the first exercise of §5's own trigger - a real
  second provider making the `provider` column and `PushMessage`-shaped port a routing seam rather than
  preparation. The schema (§1), fan-out (§2) and client-owns-loudness (§3) rulings are untouched.
- **Amended by ADR-0185** (2026-09-26): §1's revocation list gains a fourth cause - a bounded,
  timer-based prune of a row whose `last_seen_at` has not moved in 14 days - reversing this ADR's own
  "none of them is a timer" ruling for the one case `26-83`/`26-122` found it could never reach: RuStore
  answers `200` for some tokens a reinstall leaves behind, so "the provider says the token is gone"
  structurally cannot fire for them. Nothing else in §1 changes.
- **Date**: 2026-09-21
- **Stage**: 26

## Context

Stage 26 opens a native Android operator client (`26-00`, `adr/0178`). The author's stated reason for
building it at all is push: a phone in a pocket that vibrates when a visitor needs attention. Ported
literally, the console's alerting gives an Android app that notifies **only while it is in the
foreground with a live socket** — a worse notifier than the desktop console, and the opposite of the
one thing a native app is uniquely good at. `adr/0178` closes by saying so and by saying that no
client architecture makes it free.

Four facts about the current system were read from the code on 2026-09-21 and constrain the answer.

**The console's alerting is the browser `Notification` API, and it is loud about exactly two things.**
`ago-console/src/workspace/alerts.ts` holds the decision as pure functions; `useAlerts.ts` holds the
effects. `WorkspaceLayout.tsx` calls `fire()` from two hub handlers and no others: a conversation
assigned to this operator, and a **visitor** message on a conversation assigned to this operator.
`decideAlert` stays silent only when *this tab has that conversation open **and**
`document.visibilityState === "visible"`*, and `alertTextFor` deliberately never includes the message
body.

**Both of those already have a real outboxed integration event, and a third case does not exist at
all.** `ConversationAssignedToOperator` carries the `OperatorId` directly — and
`ConversationTransferredMapper` maps a transfer onto the same contract, so transfers come free.
`MessageAccepted` carries `AuthorKind` and `Sequence` but no operator, so the conversation must be
loaded, exactly as `ResolveMessageDeliveryTargetsHandler` already does for the same event. There is
**no** `ConversationStarted` contract and no mapper for one: `realtime.md` states that nothing
broadcasts "a conversation started waiting" to a site's operators, and the console polls that list
every ten seconds instead. A calendar booking's confirm-by deadline has an event
(`Ago.Calendar.Contracts.BookingPendingStateChanged`) in a different product, a different repository
and a different database, with no chat-side consumer.

**There is no push infrastructure anywhere.** A fresh grep for `fcm|firebase|apns|devicetoken|
pushnotification` across `ago-chat`, `ago-calendar`, `ago-console`, `ago-widget` and `ago-deploy`
returns nothing real, and no `Ago.Platform.*` package exists that could have supplied it.

**The presence registry is, by its own written contract, advice rather than truth.** `realtime.md`:
"Registry contents are **advice**, not truth… Any logic that would corrupt data because the registry
was stale is a bug in that logic." Its entries outlive their owner by a heartbeat TTL, and a killed
`Api` pod relies entirely on TTL expiry because `RemoveNodeAsync` is still not wired to a shutdown
hook.

Against those, the question that actually decides the design: **when an operator has a live desktop
console open, does the phone buzz?** It is the one question a reader will ask first, it cannot be
left implicit, and the obvious-sounding answer ("suppress — they're already looking") turns out to
rest on a value the architecture document calls unreliable.

## Decision

### 1. A device is a row keyed by `(operator, installation)`, never by its token

One new table, `operator_devices`, and one new Domain type, `OperatorDevice` — a small aggregate root
of one entity, in `WebhookEndpoint`'s shape. Its identity is
`unique (operator_id, installation_id)`, where `installation_id` is generated by the app and stable
for the life of that install. The FCM registration token is a **value on** that row, replaced in
place.

This is the whole of the token-rotation story, and it is why there is no sweep job. FCM tokens rotate
on reinstall, on restore, on data clear, and periodically at Google's discretion; a table keyed on the
token accumulates one dead row per rotation for ever. Keyed on the installation, registration is an
idempotent upsert (`PUT /api/v1/me/devices/{installationId}`) that the client calls on every sign-in,
from `onNewToken`, and from a periodic `WorkManager` job — the third because `onNewToken` cannot fire
for an app that was not running when the rotation happened.

A second, partial index — `unique (provider, token) where revoked_at is null` — stops one token being
live on two rows, which a restored device backup can genuinely cause.

**A device belongs to an `Operator`, not to a Keycloak identity.** `operators` is uniquely indexed on
`(external_subject_id, site_id)` and one person may hold several tenancies, so one physical phone
signed into two tenants holds two rows. That matches what the fan-out events name, and it keeps a
notification about tenant A off a device registered under tenant B.

**Revocation has exactly three causes, and none of them is a timer.** An explicit
`DELETE /api/v1/me/devices/{installationId}` on sign-out, called before the client discards its token
(the console's own sign-out makes no backend call at all, so this is a step Android has and the
console does not); the provider answering `UNREGISTERED`/`INVALID_ARGUMENT`, which is terminal and is
the mechanism that actually keeps the table clean; and `13-03`'s existing `OperatorRemovedConsumer`
gaining one extra repository call. A phone in a drawer for three weeks is not a revoked device.

### 2. The fan-out is two `Competing` consumers in `Ago.Chat.Worker`, calling one Application handler

`OperatorAssignmentPushConsumer` on `ConversationAssignedToOperator` and
`OperatorMessagePushConsumer` on `MessageAccepted` — the shape `ConversationAssignmentFanoutConsumer`
and `ChannelMessageDeliveryConsumer` already are, each with its own stable `ConsumerName`, its own
queue and its own DLQ. `MessageAccepted` gains a fifth competing subscriber, which a per-subscriber
queue name is exactly what makes safe.

The handler reuses `alerts.ts`'s own rules rather than inventing a second set: visitor messages only,
the assigned operator only, and `alertTextFor`'s text with **no message body**, carried over
unchanged for the reason that file gives — a notification is drawn over whatever is on screen and
survives in a tray this system cannot erase.

**No `inbox` idempotency row.** `adr/0020` already permits direct publication for a purely derived,
best-effort notification computed from an already-outboxed event. Idempotency comes from a collapse
key per conversation — `ago-conversation-{id}`, the identical value `useAlerts.ts` already uses as
its `Notification` `tag` — plus client-side dedupe by `MessageId`. A database write per notification,
to prevent a duplicate the collapse key already prevents, buys nothing.

### 3. The server never suppresses a push because the operator looks connected. Each client decides whether to be loud

**A push fires whether or not the operator has a live desktop session.** The server decides *who is
told*; the client decides *whether to make a noise*.

Four reasons:

- **The presence registry is advice, not truth, in writing.** Suppressing on a stale
  `presence:operator:{id}` entry is precisely the "logic that would be wrong because the registry was
  stale" `realtime.md` calls a bug in that logic.
- **A live connection is not a person looking at a screen, and the server cannot learn the
  difference.** `decideAlert` needs `document.visibilityState`, which never leaves the browser.
  Making it available means a **new** hub method — a parameter may never be added to an existing one
  (`realtime.md`, learned through `5-12` and `5-19`) — writing per-tab mutable state, on every tab
  switch, into the store already declared lossy. New machinery, for a worse decision.
- **The failure modes are not comparable.** Suppress wrongly and the operator is never told, which is
  the failure the app exists to fix and is invisible when it happens. Fail to suppress and a phone
  buzzes next to someone already reading the thread — visible immediately, and theirs to end.
- **The operator already holds a better instrument.** Notification channels, per-channel importance
  and Do Not Disturb live on the phone, where the person is.

**Suppression is therefore a client decision, and `decideAlert`'s rule is reused rather than
duplicated — it simply runs on each client.** This forces one concrete mechanism: FCM messages are
sent as **data-only messages, never `notification` payloads**, because a `notification` payload is
rendered by the system with no app code running and the app would never get to apply the rule. Cost:
they need `android.priority = "high"` to escape Doze, which is set for these two message kinds and
nothing else; and a force-stopped app receives nothing at all, which is Android's rule and not ours.

### 4. `Ago.Chat.Worker` hosts it, and holds the credential alone. No new host

`adr/0013` splits hosts by failure profile. Push's profile — one third-party HTTP endpoint, slow or
unreachable, behind a resilience policy — is the Worker's existing profile, already carried six times
over by the MAX, Telegram, VK, Avito, WhatsApp and Email adapters. `Ago.Chat.Webhooks` was split out
for a profile that does not apply: a *tenant's* own endpoint, unbounded in latency and in number,
where one tenant must not starve another.

`Ago.Chat.Api` gains only the two registration routes and never talks to FCM, so the new Google
service-account credential (`FCM_SERVICE_ACCOUNT_JSON`, `infra-credentials`, rotation class
**Restart**, trivially **Draining** because a service account may hold two keys at once) reaches
exactly one deployable and never the internet-facing one. `ago-console` is untouched.

### 5. `provider` is a column and `IPushSender` takes a `PushMessage`. Nothing else is built for iOS

Both are by-products of doing Android cleanly, not preparation: a `token` column with no `provider`
beside it lies about what it holds the day a second kind of token exists, and a port whose signature
is an FCM request has the adapter's vocabulary in it, which is a layering fault today regardless of
iOS.

Deliberately **not** built: no `Ago.Chat.Infrastructure.Apns` project, empty or otherwise; no
provider registry, strategy resolver or `IPushSenderFactory` — one implementation is registered
directly, because a dispatch table with one entry is a guess about the second; and no abstracted
notion of notification content, because `PushMessage` carries what `alertTextFor` already decided this
product's one notification is.

**The trigger that reopens it** is the first real iOS device registration, when the question becomes
whether `IPushSender` gains a second implementation or APNs earns its own port.

### 6. Two measurements gate the implementation, and this ADR does not pre-empt either

Neither is assumed, in the same way `14-05` gated Telegram on a real spike before a line of the
adapter was written.

**Reachability of `fcm.googleapis.com` and `oauth2.googleapis.com` from the live node**, by
`adr/0070`'s own method. That ADR found 8 of 15 attempts to `api.telegram.org` never established TCP
from this VPS, and its control run — 5 of 5 to `https://www.google.com`, 121–402 ms, 2026-08-28 — is
relevant evidence and not proof: different hostname, different service, three weeks old. If either
host needs the relay, the adapter gets a proxy-aware `HttpClient` wired in the composition root
exactly as `TelegramProxyOptions` documents.

**Google Play Services on the operator's own phone.** FCM does not exist without it, and no backend
design substitutes. Named as a product risk, not solved.

## Consequences

**What this buys.** The single feature the Android app exists for, built out of mechanisms this
codebase already proves in production: an outboxed event, a `Competing` Worker consumer, a port with
an Infrastructure adapter carrying its own resilience, a DLQ, and one table. Transfers are covered for
free because they already map onto the assignment contract. `ago-console` changes not at all, and the
FCM credential reaches exactly one of three deployables — the one that is not internet-facing.

**What becomes harder.** There are now **two** places that decide when a notification is warranted —
`alerts.ts` in TypeScript and its counterpart in Kotlin — and they can drift. That is accepted
knowingly and is the direct price of §3: the alternative was one server-side decision built on a value
the architecture document calls advice. The duplication is small, visible, and unit-testable on both
sides, which is the same trade `adr/0027` and `adr/0178` each took over a shared abstraction.

A redelivered event separated by more than the user's own dismissal will buzz twice. It is a buzz, not
a corrupted counter, and the stores that hold real state keep their `IInboxChecker` rows unchanged.

**What has to be maintained.** Three things, each of which fails quietly if forgotten. The
`ON DELETE CASCADE` from `operator_devices.site_id` must genuinely be reached by
`SiteErasureQuery`'s own `delete from sites` — `adr/0168`'s Consequences record that exact assumption
failing once already (`25-78`). `secrets.md` and `tools/secrets-audit.sh` must gain the new key in the
same change, or the audit fails, which is what the audit is for. And `personal-data.md`'s destinations
table and `processing-instruction-facts.md` must gain a Google/FCM row that reads differently from
every other row in it: the data subject is an **operator**, so by `adr/0076` AGO is the controller and
this transfer is AGO's own decision rather than one made on a tenant's instruction.

**An open question this ADR deliberately does not close.** `personal-data.md`'s data-residency
constraint says the default answer for a new destination is "in Russia" and that moving one out is a
decision made explicitly, in writing, with the legal question asked first. FCM is a Google destination
and there is no Russian alternative that reaches a stock Android phone. The question is the author's
to ask and is a precondition on the implementation item, not on this design. The mitigation available
regardless is minimisation, and it is already taken: no message body, no visitor identity beyond a
truncated pseudonym, no conversation content.

**No per-send audit table**, deliberately, unlike `WebhookDelivery` and `ChannelDelivery`. A row per
push grows with traffic and would be a durable log of when each operator was told about which
conversation — the "growing store of who did what, when" shape `personal-data.md` already rejected
when it refused a deletion journal. What makes a dead device visible instead is bounded by device
count: `last_failure_at`/`failure_reason` on the row, plus `ago.chat.push.sends`,
`ago.chat.push.suppressed` and `ago.chat.push.tokens_revoked`. The condition that means *push itself
is dead* is a pairing rather than any single number — `7-08`'s existing
`ago.chat.delivery.recipients{recipient_kind="operator",presence="absent"}` rising while the push
counter stays flat. Following `7-08`'s own restraint, **no alert threshold is set here**; `15-03`
sets those from real data.

## Alternatives considered

**Suppress the push when the registry says the operator has a live connection.** The intuitive answer
and the one a reviewer will expect. It loses on the registry's own contract — `realtime.md` calls its
contents advice, not truth, and a stale entry outlives its owner by a heartbeat TTL, longer for a pod
killed before `RemoveNodeAsync` is ever wired. It also answers the wrong question: a live socket is
not a person looking at a screen, so even a perfectly fresh registry would suppress notifications for
an operator who alt-tabbed away — the exact case `decideAlert` was written to get right.

**Add a visibility signal from the console so the server can suppress correctly.** The honest version
of the alternative above, and it is rejected on cost rather than on principle. It needs a new hub
method (a parameter may never be added to an existing one), a write on every tab switch, and a new
piece of per-connection mutable state in Redis — to move a decision *out of* the place that can make
it correctly for free, *into* the place this project already declared lossy.

**Reuse `INodeFanoutPublisher`'s `FanoutResult` and push only to operators it reported as absent.**
Genuinely tempting, because that value already exists at exactly the right moment and costs nothing to
read. Rejected for the same reason as the first alternative — it is the registry's number, with the
registry's staleness — and it would additionally couple a durable notification path to a best-effort
realtime one, so a fan-out failure would silently become a push failure.

**A `notification` payload instead of a data-only message.** Simpler, survives a killed app process,
and needs no client code at all. It loses because the system renders it with no app code running, so
the client can never apply `decideAlert` — which, given §3, would mean no suppression anywhere and a
phone that buzzes at an operator mid-sentence in the very conversation on their screen.

**A new `Ago.Chat.Push` host.** Rejected by `adr/0013`'s own test: hosts split by failure profile, and
this profile is the Worker's existing one, already carried six times. A seventh outbound integration
is not a new failure mode.

**A per-operator device registered against the Keycloak identity rather than the `Operator` row.** One
row per physical phone instead of one per tenancy, which sounds tidier. Rejected: the fan-out events
name an `OperatorId`, so this adds a lookup to reach the same answer, and it would let a notification
about one tenant's visitor land on a device registered while the operator was working for another —
against `tenant-isolation.md`'s central claim.

**A `push_deliveries` table, one row per send, mirroring `WebhookDelivery`.** Rejected above on
volume and on `personal-data.md`'s own reasoning; the observability it would buy is bought instead by
three counters and two columns that do not grow with traffic.

**Web Push for the console in the same change, so both clients share one fan-out.** Attractive, and
deferred rather than refused: it is a second client, a second provider vocabulary (VAPID), and a
change to a feature that currently works — none of which the Android app needs, and all of which
would have to be re-argued if the Android measurement in §6 came back badly.

**Poll from the phone instead of pushing.** The only design that needs no Google dependency and no new
credential at all. It loses on the actual requirement: a phone cannot poll from a pocket without
either draining the battery or being throttled by Doze into exactly the latency push exists to remove.
