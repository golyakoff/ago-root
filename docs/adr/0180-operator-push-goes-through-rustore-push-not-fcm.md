# ADR-0180: Operator push goes through RuStore Push, not FCM — and RuStore's distributor model replaces three of ADR-0179's mechanics

- **Status**: Accepted
- **Date**: 2026-09-21
- **Stage**: 26
- **Supersedes**: part of ADR-0179 — its provider choice and everything downstream of it (the
  credential, the collapse key, the priority flag, the adapter project, and §6's two measurements).
  Its schema, its consumer shape, its client-owns-loudness decision and its no-new-host ruling all
  stand; §"What ADR-0179 keeps, and it is most of it" lists them by name.

## Context

`adr/0179` designed operator push one day before this. Everything in it above the line *which
provider* — the `operator_devices` row keyed `(operator_id, installation_id)`, the two `Competing`
Worker consumers, the answer that the server never suppresses on presence, the refusal of a new host
— was argued from this codebase's own facts and from `realtime.md`'s own contract, and none of it
mentions Google. Everything below that line was FCM.

`adr/0179` closed with an open question it deliberately did not answer:

> `personal-data.md`'s data-residency constraint says the default answer for a new destination is "in
> Russia" and that moving one out is a decision made explicitly, in writing, with the legal question
> asked first. FCM is a Google destination and there is no Russian alternative that reaches a stock
> Android phone. The question is the author's to ask and is a precondition on the implementation item.

`26-04` carried that as a blocking gate and has not started.

**The author answered by changing the provider rather than by answering the question.** RuStore Push
is Russian infrastructure (VK), so `personal-data.md`'s default is satisfied on its own terms and the
written legal escalation is not needed at all. The author accepted the trade-off in his own words —
*"менее задокументированный SDK и придётся это исследовать с нуля"* (a less documented SDK, and it
will have to be researched from scratch).

Two pieces of context keep this honest rather than overstated. **There are zero real tenants today**
and not one operator token exists in any table, so this is not a compliance response to an exposure;
it is taking the cheaper answer while it is still free to take, before an adapter is written. And
the sentence `adr/0179` wrote — *"there is no Russian alternative that reaches a stock Android
phone"* — turns out to be **wrong in the letter and right in the spirit**, which §4 and §5 below set
out: RuStore Push does reach an Android phone without Google, but only one that carries a
distributor app, and that is a different adoption problem rather than none.

Everything that follows about RuStore Push was read from RuStore's own developer documentation on
2026-09-21 (Push SDK for Kotlin/Java 7.0.0, its release history, and the send-API reference), and is
cited as such. Where the documentation does not answer a question, this ADR says so instead of
filling it in — the SDK really is thinner than Google's, which is the cost the author accepted.

## Decision

### 1. The provider is RuStore Push. One host, one long-lived bearer token, an FCM-shaped request

`provider = 'rustore'` on the device row. The send API is a single call:

```
POST https://vkpns.rustore.ru/v1/projects/{projectId}/messages:send
Authorization: Bearer {service-token}
Content-Type: application/json
```

Both values come from RuStore Console (app page → Push notifications → Projects). RuStore's own
documentation opens the page by saying the API *"was designed to provide a drop-in replacement for
Firebase"*, and the request body bears that out: `message.token`, `message.data`,
`message.notification`, `message.android`.

**This is simpler than what `adr/0179` designed, in one specific way that matters to §8.** FCM v1
needs a service-account JSON minted into an OAuth2 bearer on every send, which is a second host and a
second chance to fail. RuStore's service token is presented directly. **There is one hostname to
reach, not two.**

### 2. The credential changes shape, and its rotation class is no longer free

`FCM_SERVICE_ACCOUNT_JSON` is replaced by **`RUSTORE_PUSH_SERVICE_TOKEN`** — same Secret
(`infra-credentials`), same single reader (`Ago.Chat.Worker`), same absence from the internet-facing
`Ago.Chat.Api`. `secrets.md` and `tools/secrets-audit.sh` gain the new key in the same change, or the
audit fails, which is what the audit is for.

The **project ID is not a secret and must not be treated as one**: it ships inside the app's own
`AndroidManifest.xml` as `ru.rustore.sdk.pushclient.project_id`, so it is readable from any copy of
the APK. It is still supplied as deploy-time configuration rather than committed, on the ordinary
ground that these repositories are public and a deployment identifier belongs in `.env` with its
neighbours.

**`adr/0179` claimed rotation class Restart, "trivially Draining because a Google service account may
hold two keys at once". That claim does not carry over and is not replaced by a guess.** RuStore's
documentation does not state whether a push project may hold two live service tokens, or whether
issuing a new one invalidates the old. So the class recorded here is **Restart**, and whether it can
be made Draining is an open question for whoever first opens the console — a fact to observe, not to
assert.

### 3. Data-only messages survive, and with them the whole of §3. This was the load-bearing check

`adr/0179` §3's answer — *the server decides who is told; each client decides whether to be loud* —
is only implementable if the app receives the message with no system-rendered notification. Under
FCM that forced data-only messages. The question was whether RuStore Push can do the same, and if it
could not, §3 would have fallen with it.

**It can, and RuStore states it directly on both halves.**

On the client, the SDK's `onMessageReceived` documentation: if the `notification` object carries
data, the RuStore SDK renders the notification itself; to prevent that, use the `data` object and
leave `notification` empty — and the method *"вызывается в любом случае"* (is called in any case).
On the server, the send API's own validation algorithm: if `message.data` is present and non-empty
the message is valid, and `message.notification` and `message.android` *"may be omitted"*.

So §3 stands unchanged. `RuStoreMessagingService.onMessageReceived(message: RemoteMessage)` takes
`FirebaseMessagingService`'s place, `message.data` carries the payload, and the app applies
`decideAlert`'s rule before it renders anything. The trap is identical to FCM's and is avoided the
identical way: a non-empty `notification` block would be drawn by the SDK with the app's own rule
never consulted.

**One detail is genuinely ambiguous and is named rather than guessed.** The published validation rule
is written as *"if `message.data.payload` is present and non-empty"*, while `message.data` is typed
in the same document as a flat `map[string]string`. Whether a data-only message must carry a key
literally named `payload`, or whether that is loose wording for the data map itself, is not
answerable from the documentation. **`26-04`'s first real send settles it. Nothing here assumes
either reading**, and an adapter written to one of them without checking is the kind of invented
detail this project's rules forbid.

### 4. Three FCM mechanics have no RuStore equivalent. Two were load-bearing

**(a) The collapse key is gone from the wire, and the idempotency story changes shape.**

`adr/0179` §2 refused an `inbox` row and rested idempotency on two mechanisms: an FCM collapse key
`ago-conversation-{conversationId}`, and client-side dedupe by `MessageId`. The first does not exist
here. RuStore's send schema has no `collapse_key` field — the page states *"At the moment, only the
fields listed above are supported in the message structure"* — and on the client,
`RemoteMessage.collapseKey` is documented as *"на данный момент не учитывается"* (not currently taken
into account).

**The decision to have no `inbox` row is unchanged, because the half that was actually doing the work
is the half that survives.** `useAlerts.ts` collapses *delivered* notifications by reusing one
`Notification` tag; since §3 already renders the notification in app code, the client calls
`NotificationManagerCompat.notify` with the same `ago-conversation-{conversationId}` tag and gets
exactly that behaviour. `RemoteMessage.messageId` exists, so dedupe by message id has a real field to
key on. `adr/0020`'s permission for a purely derived, best-effort notification is untouched.

*What is genuinely lost*, stated so nobody discovers it later: FCM additionally collapsed **undelivered**
messages queued for an offline phone. RuStore does not. A phone that was off the network and comes
back may receive several queued pushes for one conversation and collapse them into one card on
arrival, rather than having received one. Same card, more radio traffic, more `onMessageReceived`
calls. A buzz, not a corrupted counter — the same reading `adr/0179` gave the redelivery case.

**(b) There is no priority field, so the Doze argument is replaced rather than carried over.**

`adr/0179` §3 accepted `android.priority = "high"` as a named cost of data-only messages, set for
these two message kinds and nothing else, because *"Google throttles apps that overuse it"*. RuStore
has no such field to set: it is absent from the documented send schema, and the client-side
`RemoteMessage.priority` is likewise *"на данный момент не учитывается"*. There is nothing to set,
nothing to be throttled for — and equally **no documented lever for asking that a message arrive
promptly.** That sentence in `adr/0179` is simply deleted rather than translated.

**(c) Delivery is a distributor app polling a server, not a transport this product or the OS owns.**

This is the largest technical difference between the two providers and a reader must not be allowed
to miss it. RuStore's own SDK page opens with the mechanism: a **distributor** app must be installed
on the device; it periodically asks the server whether anything is waiting for apps that embed the
SDK, and forwards what it finds to them. RuStore itself is the primary distributor; where it is
absent, *"one of the other VK applications"* may take the role, chosen **remotely on the server**,
and RuStore explicitly declines to publish the list of possible fallbacks, noting the set can change
and that the distributor on a given device may be a different app at any moment. Only one app acts as
distributor at a time; the rest sleep, and a new one is selected automatically if the current one is
removed or its settings change.

Two consequences follow and neither is a footnote:

- **Latency is unspecified.** The documentation gives no polling interval, no delivery-time target,
  and — per (b) — no priority lever. **This design therefore makes no latency claim whatsoever.**
  Rule 7 forbids inventing one, and measuring it is a gate on `26-04`/`26-18`, not an assumption here.
- **A device that has RuStore but denies it background permission still receives pushes, RuStore's
  own docs say, "но со значительной задержкой"** — with significant delay. That is a per-device
  setting nothing on the server can observe or correct.

### 5. The device prerequisites are RuStore's, they are longer than FCM's, and they are a product question

`adr/0179` §6 named one client-side prerequisite — Google Play Services — as a product risk it did
not solve. RuStore's own conditions list is longer. Quoted as conditions, from the SDK page:

1. A **distributor app is installed** (RuStore, or an undisclosed fallback). The documented check is
   `RuStorePushClient.checkPushAvailability()`, returning `FeatureAvailabilityResult.Available` or
   `Unavailable(cause)`; the cause for an absent distributor is `HostAppNotInstalledException`.
2. If RuStore is installed, it is **allowed to run in the background** — otherwise the significant
   delay above. Surfaced to the app as `HostAppBackgroundWorkPermissionNotGranted`, which RuStore
   describes as non-critical.
3. The **user is authorized in RuStore**. Surfaced as `UnauthorizedException`, with the documented
   caveat that it may not be raised even when the user is unauthorized, because the behaviour is
   controlled dynamically — so an app must handle it without relying on it.
4. The **signature fingerprint** of the installed build matches the one registered under Push
   notifications → Projects in RuStore Console. Because debug and release signatures and package
   names differ, RuStore requires **a separate console project per build type**.
5. App data uploaded in that console section, and a current SDK version in use.

**Read against `adr/0179` §6.2, this is a harder product question, not an easier one, and saying so
is the point of writing it down.** FCM's prerequisite is Google Play Services, absent on de-Googled
ROMs and on some devices sold in this deployment's market. RuStore Push's prerequisite is that the
operator's phone carries RuStore (or an unnamed VK app), that the operator is *signed in to it*, and
that it is not battery-restricted. Requirement 3 in particular means the operator must hold a
**RuStore account** — a second identity this product neither controls nor can provision.

This trades one adoption question for another. It does not remove it. Whether the trade is right is
the author's call and this ADR makes it visible rather than burying it; it is the single finding here
most likely to change a mind. What is strictly better than `adr/0179` had is that the condition is
now **programmatically checkable on the device** — `checkPushAvailability()` — where "does this phone
have Play Services" was named with no API beside it.

### 6. A message's `ttl` becomes a real decision, because the default is four weeks

RuStore's documented default, when `ttl` is absent or zero, is **four weeks** — and if
`message.android` is missing entirely it is added with the `ttl` field. A notification saying a
visitor is waiting is worthless long after the fact; delivered four weeks later it is noise that
costs an operator trust in the whole feature.

So **`android.ttl` is set explicitly on every send, short.** The number itself is not decided here,
because this project does not invent numbers: `26-04` chooses it, states the reasoning, and records
it. What is decided here is that leaving it unset is wrong. Maximum message size is 4096 bytes, which
`alertTextFor`'s body-free text is nowhere near.

### 7. The client SDK, by its real names

For `26-06` and `26-18`, so neither item has to guess at a plausible-sounding API:

| | |
|---|---|
| Maven repository | `https://nexus-external.rustore.ru/repository/maven-rustore-exposed/` |
| Dependency | `ru.rustore.sdk:pushclient` — **7.4.0** is the newest in the published release history as of 2026-09-21 |
| Minimum Kotlin | 1.8 |
| Credentials file | **None.** There is no `google-services.json` equivalent — initialisation takes a project-ID string |
| Initialisation | `RuStorePushClient.init(application, projectId, logger)`, or automatic via the `ru.rustore.sdk.pushclient.project_id` manifest meta-data. Not multi-process safe: initialise in the main process only |
| Receiver | A service extending `RuStoreMessagingService`, declared in the manifest with `android:exported="true"` and an intent filter on `ru.rustore.sdk.pushclient.MESSAGING_EVENT` |
| Callbacks | `onNewToken(token)`, `onMessageReceived(message: RemoteMessage)`, `onDeletedMessages()`, `onError(errors: List<RuStorePushClientException>)` — all on a background thread |
| Token | `RuStorePushClient.getToken()` (creates one if absent), `deleteToken()` |
| Availability | `RuStorePushClient.checkPushAvailability()` |
| Notification permission | `POST_NOTIFICATIONS` is in the SDK's manifest from 1.4.0; the app must still request it at runtime on Android 13+ |
| Hard constraint | **A `RuStoreMessagingService` method has 20 seconds to finish**; after that the system may kill the service (6.2.1 made the shutdown deterministic) |

**`onNewToken` is the same callback shape `adr/0179` §1 already designed all three registration call
sites around, so none of them change in purpose.** RuStore tokens rotate too: the SDK's own release
history records two separate releases (6.8.0 and 6.9.1) that changed reissue logic so tokens are
reissued *less* often — which is confirmation that they are reissued, and the reason `adr/0179`'s
installation-keyed row stays exactly right.

**`onDeletedMessages()` is a new affordance FCM's design did not name**: RuStore calls it when one or
more pushes were not delivered (for example, TTL expiry), and recommends syncing with your own server
so data is not missed. `26-18` gets it for free as a recovery hook, with the conversation list it
already has as the thing to refresh.

### 8. What ADR-0179 keeps, and it is most of it

Stated explicitly, because a supersession that does not say what survives leaves a reader unable to
trust either document.

- **§1 entire.** `operator_devices`, `unique (operator_id, installation_id)`, the token as a *value
  on* the row rather than its identity, `unique (provider, token) where revoked_at is null`, a device
  belonging to an `Operator` rather than a Keycloak identity, and revocation by exactly three causes
  with no timer among them. The only word that changes is which provider the token came from.
- **§2 entire, minus the collapse key** (§4a above). Two `Competing` consumers with their own
  `ConsumerName`s and DLQs, one Application handler, `alerts.ts`'s own rules reused rather than
  reinvented, `alertTextFor`'s never-the-message-body decision, and no `inbox` row.
- **§3's decision entire.** The server never suppresses because the operator looks connected; the
  registry is advice not truth; a live socket is not a person looking at a screen; the failure modes
  are not comparable; the client decides loudness. Only the mechanics under it change.
- **§4 entire.** `Ago.Chat.Worker` hosts it and holds the credential alone; `Ago.Chat.Api` gains the
  two registration routes and talks to no provider; `ago-console` is untouched; no new host. The
  argument was `adr/0013`'s failure-profile test, which never mentioned Google.
- **§5 entire — and this change is the first evidence it was right.** `adr/0179` argued that the
  `provider` column and a `PushMessage`-shaped `IPushSender` were by-products of doing Android
  cleanly rather than preparation for iOS. The provider changed before one line of adapter code
  existed, and neither the column nor the port's signature needed to move. The refusals stand too: no
  APNs project, no provider registry, no `IPushSenderFactory`, and the trigger that reopens it is
  still a real iOS device registering.
- **Its Consequences entire, minus the residency paragraph and the credential's rotation class.** The
  two-places-decide-loudness cost and why it is accepted; no per-send audit table; the three counters
  (`ago.chat.push.sends`, `.suppressed`, `.tokens_revoked`); the `ON DELETE CASCADE` verification
  `25-78` proves cannot be assumed; the `7-08` pairing that makes a dead consumer visible; `15-03`
  setting thresholds from real data rather than a guess made here.

### 9. Token revocation keeps its mechanism, on different codes

`adr/0179`'s table stays clean because the provider says when a token is gone. RuStore says it too,
with its own vocabulary. Its documented error body carries `code`, `message` and `status`, HTTP
status matching `code`:

| Outcome | HTTP | `status` | Treatment |
|---|---|---|---|
| Malformed push token | 400 | `INVALID_ARGUMENT` | Terminal — revoke the row |
| Valid token that has expired | 404 | `NOT_FOUND` | Terminal — revoke the row |
| Bad service key | 403 | `PERMISSION_DENIED` | **Never** a device fault — this is our credential, and it must not revoke anybody's row |
| Rate limited | 429 | `TOO_MANY_REQUESTS` | Transient — back off, record `last_failure_at` |
| Server error | 500 | `INTERNAL` | Transient |

**The adapter keys revocation on `status` and `code`, never on `message` text.** RuStore's own
published example of a malformed-token response carries the message *"The registration token is not a
valid FCM registration token"* — a Firebase string surviving inside a RuStore error body. It is real
evidence for the drop-in-replacement claim and a good reason to trust the field with a documented
enumeration over the one that is prose.

Two honest gaps. The `status` field's own description lists `UNREGISTERED` among its example values,
while the page's enumerated "possible errors" list does not include it — so an adapter should treat
`UNREGISTERED` as terminal if it ever arrives, without depending on it. And **no numeric rate limit
is published anywhere**: `TOO_MANY_REQUESTS` exists, its threshold does not. This design claims no
throughput figure.

### 10. §6's measurements, restated as one runtime gate and one build gate

**Runtime reachability: `vkpns.rustore.ru`, and nothing else.** `adr/0179` needed two Google hosts
because the token mint is separate; there is no mint here. Measured by `adr/0070`'s own method — N
requests, spaced, fixed timeout, **a deliberately invalid service token so an HTTP 403
`PERMISSION_DENIED` proves a complete round trip** (`adr/0179` used FCM's 401 for the same purpose;
403 is RuStore's own documented code for a bad service key).

`adr/0070`'s control run is **less** relevant here than it was for FCM, not more, and pretending
otherwise would be the exact error `adr/0179` warned against when it called that run "relevant
evidence and not proof". It measured `https://www.google.com` from this VPS. A Russian host reached
from a VPS in Russia is a different question its data says nothing about. If a relay turns out to be
needed, the shape is already known — a proxy-aware `HttpClient` in the composition root, as
`TelegramProxyOptions` documents.

**Build-time reachability: `nexus-external.rustore.ru`.** `ago-android`'s CI has never fetched from a
RuStore repository and its reachability from GitHub Actions is unestablished. A build-time dependency
is a smaller risk than a runtime one but it is not zero, and a green local build proves nothing about
the runner. Only the `nexus-external` address is used: RuStore's docs say the older
`artifactory-external.vkpartner.ru` address *"may stop working at some point"*. (A third-party issue
tracker names 2026-10-01 for that retirement — **secondary, unverified, and not relied on**; the
reason to use only the new address is RuStore's own sentence, not that date.)

**The client-side gate replaces `adr/0179`'s Play Services question with a better-shaped one**:
`RuStorePushClient.checkPushAvailability()` returning `Available` on the operator's own phone, which
is an API call `26-18` can make and report rather than a fact somebody has to eyeball.

## Consequences

**What this buys.** The residency question closes without a legal escalation, and closes at the
cheapest possible moment: zero real tenants, no operator token in any table, no adapter written.
`26-04` loses the blocker that was keeping it out of work. The credential gets genuinely simpler —
one long-lived bearer against one host, no OAuth2 mint, no JSON key file, no Google project, and one
fewer hostname whose reachability has to be established.

**What becomes harder. Three things, and none of them is small.**

1. **Delivery timing is unspecified and unlevered.** No priority field, a distributor app polling on
   an interval nobody publishes, and a documented warning that a background-restricted RuStore means
   *significant* delay. The product's single promise — the phone buzzes while it is in a pocket — now
   rests on a number this project has not measured and its own rule 7 forbids inventing. Under FCM
   there was at least a lever and a documented Doze story; here there is neither.
2. **The prerequisite set is longer and less commonly satisfied.** Four device conditions plus a
   console project per build type, and one of them requires the operator to hold and be signed into a
   RuStore account. A new operator's phone can satisfy none of these, and nothing on the server can
   see that it does not — only `checkPushAvailability()` on the device can, which is why `26-18` must
   report it rather than fail quietly.
3. **The documentation is thinner, which is exactly what the author accepted.** Concretely, and
   listed so the gaps are gates rather than surprises: no published rate limit behind
   `TOO_MANY_REQUESTS`; no statement of whether a push project can hold two live service tokens (so
   no rotation-class claim, §2); no polling interval or delivery-time target (§4c); a validation rule
   written against `message.data.payload` while `data` is typed as a flat map (§3); and no published
   statement of whether push works for an app registered in the console but never published through
   RuStore, which is a real question for an operator app the author may want to distribute directly.

**What has to be maintained.** Unchanged from `adr/0179` in kind, changed in content: `secrets.md`
and `tools/secrets-audit.sh` gain `RUSTORE_PUSH_SERVICE_TOKEN` in the same change that introduces it;
`personal-data.md`'s destinations table and `processing-instruction-facts.md` gain a row naming
VK/RuStore rather than Google; the `ON DELETE CASCADE` from `operator_devices.site_id` must still be
proved against `SiteErasureQuery` rather than assumed, for the reason `25-78` already demonstrated.

**The personal-data row still reads differently from every other row, and for the same reason.** The
subject is an **operator**, so by `adr/0076` AGO is the controller and this transfer is AGO's own
decision rather than one made on a tenant's instruction. Changing the destination's nationality does
not change that. What crosses is unchanged and still minimal: a device token, a title, a body naming
a truncated pseudonymous visitor id, a conversation id, **never a message body**.

**One thing about the delivery path is new and belongs in that row rather than being discovered
later.** Under FCM the payload passed through Google's servers and then Google Play Services, a
single named system component. Under RuStore it passes through RuStore's servers and then through
**whichever distributor app is currently elected on that operator's own device** — RuStore names
itself as primary, declines to enumerate the fallbacks, and says the election can change. That is a
wider and less-named delivery path than FCM's, even though every hop is domestic, and the honest
version of the residency row says so.

**No claim is made that this is more private than FCM.** It is closer, under a Russian legal regime,
which is what `personal-data.md`'s default asks for — nothing more.

## Alternatives considered

**FCM, which is what `adr/0179` chose and what most teams would pick.** It deserves a real hearing
and it wins on nearly every technical axis: documentation of an entirely different order, an error
vocabulary this design was already written against, a `collapse_key` that exists, a `priority` lever
with a documented Doze story, an OS-level transport rather than a polling distributor app, published
quotas, and a prerequisite — Google Play Services — that most stock Android phones already satisfy
with no user action and no second account. It loses on exactly one thing, and it is the thing the
author decided: `personal-data.md`'s default answer for a new destination is "in Russia", FCM is a
Google destination, and moving a destination out is a decision that must be made explicitly, in
writing, with the legal question asked first. Choosing RuStore is not an answer to that question — it
is a decision not to have to ask it. Stated in its weakest honest form: **nobody's data is at risk
today**, because there are no real tenants and no tokens; this is taking the cheap option while it is
still cheap, before an adapter exists and before anyone's token is in a table, rather than a response
to an exposure. The price is enumerated in Consequences above and the author accepted it in those
terms.

**RuStore's Universal Push API — `POST https://vkpns-universal.rustore.ru/v1/send`, which fans one
request out through RuStore, FCM, HMS and APNS.** Genuinely attractive on two counts: it is one API
for the iOS client `adr/0178` says is coming, and it would let a device with no distributor fall back
to FCM — the direct answer to §5's prerequisite problem, which is this decision's worst consequence.
Rejected, and the reason is this ADR's entire premise: a design that reaches FCM whenever RuStore is
unavailable has the Google destination back, just conditionally and far less visibly than before.
It is also worse operationally for the same goal — RuStore's documentation states that each
provider's own credentials travel **in the request body** and that RuStore does not store them, so
the Worker would be holding a Google service account after all, which §2 just removed. Named as the
**reopening point**: if `26-18`'s prerequisite measurement comes back badly, this is the first thing
to reconsider — with the residency question then asked properly rather than routed around.

**Keep `adr/0179` and answer the legal question instead.** The honest alternative, and the one
`adr/0179` itself named. It is more work with no deadline anybody controls, and it produces a written
legal position this project would then have to maintain and revisit. It remains fully available:
nothing here forecloses it, and `adr/0179` §5's `provider` column plus the `PushMessage`-shaped port
mean returning to FCM would be one new adapter rather than a redesign — which is the strongest
argument that this is a reversible decision rather than a one-way door.

**Amend `adr/0179` in place instead of writing this.** Rejected on this directory's own convention:
`adr/0027` and `adr/0091` are each marked partially superseded with their text left untouched, for
the reason `adr/0027`'s own banner gives — *"editing accepted reasoning destroys the only thing a
record like this is for."* Most of `0179` is still correct and still the live design, which is
precisely why it is marked partially rather than wholly superseded.

**Huawei HMS Push.** Trades a Google dependency for a different foreign one, needs Huawei Mobile
Services on the phone, and is strictly worse on both the residency ground and the prerequisite
ground. No reading of `personal-data.md` prefers it.

**A self-hosted push transport — UnifiedPush, ntfy, or a long-lived socket of this product's own.**
The only option with no third party at all, and the one that most obviously satisfies residency. It
loses for the reason `adr/0179` already rejected polling from the phone, wearing a different hat:
something has to hold a connection from the device, fight Doze for it, and survive process death —
that is an operating-system-vendor's job, and taking it on would be the single largest piece of
infrastructure in this product, built for one screen of one client.

**Write the adapter against both providers and choose at run time.** That is `adr/0179` §5's already
rejected provider registry, and nothing here changes its reasoning: a dispatch table with one entry
is a guess about the second. `provider` being a column means the second implementation is a code
change when a real second device appears, which is the whole point of having it.
