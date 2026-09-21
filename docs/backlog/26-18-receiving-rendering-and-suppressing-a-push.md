# 26-18 · Receiving, rendering and suppressing a push

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the second half of the Android client item
  `docs/architecture/push-notifications.md` names at its foot; `26-06` is the first. Split on
  promises per rule 15: *the server knows about this device* and *the phone buzzes correctly* are
  separately true or false, and each lands green on its own.
- **Verified**: 2026-09-21 — `ago-console/src/workspace/alerts.ts` and `useAlerts.ts` exist and are
  the rules being ported; `adr/0179` §3 is the decision that the server never suppresses on presence
  and that **each client decides whether to be loud**. The RuStore SDK names below are read from
  RuStore's own Kotlin/Java Push SDK documentation, same date.
- **Provider changed**: 2026-09-21. `adr/0180` replaced FCM with **RuStore Push**. `adr/0179` §3
  survives intact — the load-bearing check was whether RuStore can deliver a message without the
  system drawing it, and it can — but three mechanics underneath it changed, and each has a bullet
  below: **the collapse key is gone from the wire**, **there is no `priority` field at all**, and
  **delivery is a distributor app polling rather than an OS transport**.
- **Depends on**: `26-06` (a registered device), `26-15` (a thread to open on a tap), and — for the
  end-to-end proof — `26-04` and `26-05`. Before those land, a message can be sent to a known token
  by hand with a single `curl` at
  `POST https://vkpns.rustore.ru/v1/projects/{projectId}/messages:send`; say which path was used for
  each Done-when box. **Do not use the SDK's own `testModeEnabled`/`sendTestNotification` path for
  any box here** — RuStore states it does not interact with the backend at all, so it proves client
  wiring and nothing about delivery.

## What this item is

A push arrives on a real phone, is rendered or deliberately silenced by the same rule the console
already applies, and tapping it lands on the right thread. One promise: **the operator learns a
visitor is waiting while the phone is in their pocket** — which is `plan.md`'s stated reason this app
exists at all.

## Scope

- **A `RuStoreMessagingService` handling data-only messages, never `notification` payloads.** A
  non-empty `notification` object is rendered **by the RuStore SDK itself** with no app code
  consulted, which would throw away the whole suppression decision below; RuStore's own doc says to
  use `data` and leave `notification` empty for exactly this reason, and that `onMessageReceived` is
  called *in any case*. The payload arrives as `message.data: Map<String, String>` on a
  `RemoteMessage`, which also carries `messageId`, `ttl` and `from`.
  Three costs, and **the first is not the one `adr/0179` named**:
  - **There is no priority lever.** RuStore's send schema has no `priority` field and its
    `RemoteMessage.priority` is documented as *not currently taken into account*, so the FCM-era
    `android: { priority: "high" }` requirement is deleted rather than translated. Nothing to set,
    nothing to be throttled for, and no documented way to ask for prompt delivery.
  - A force-stopped app receives nothing at all — Android's rule, not a design choice.
  - **The service has 20 seconds** to finish handling any callback before the system may kill it
    (RuStore's own warning). Rendering a notification fits; a network round trip on the receive path
    does not, which is why the payload carries what the notification needs.
- **`decideAlert`'s rule, in Kotlin** — silent exactly when *this conversation is open **and** the
  screen is actually in front of the user*. It is reused, not re-invented: the design's own sentence
  is "the server decides who is told; each client decides whether to be loud", and `alerts.ts` put
  that decision on the client in the first place.
- **Notification channels for the kinds the fan-out actually sends** — an assigned conversation, and a
  visitor message on an assigned conversation. **Only those two.** `26-05` sends nothing else, and a
  channel for an event nothing emits is a switch that lies; `26-19` renders the channels that exist
  rather than the five the mockup drew.
- **Never the message body.** The payload does not carry one and the notification must not invent one
  from anything it does have. `alerts.ts` argued this for a desktop notification drawn over whatever
  is on screen; a lock screen in a shop with customers in the room makes the argument stronger, not
  weaker.
- **The notification tag `ago-conversation-{conversationId}`**, matching `useAlerts.ts`'s own
  `Notification` tag exactly — a visitor sending four messages replaces its own card rather than
  stacking four — **plus client-side dedupe by the payload's own message id**. Together those are the
  idempotency `26-05` deliberately has no inbox row for, and **this item now owns *both* halves
  rather than one**: RuStore has no `collapse_key` on the wire (its send schema has no such field and
  `RemoteMessage.collapseKey` is documented as not currently taken into account), so the server-side
  half of `adr/0179`'s mechanism does not exist. What survives is the half that was always doing the
  work — `NotificationManagerCompat.notify` with that tag, collapsing *delivered* notifications.
  *The named consequence:* a phone that was off the network may receive several queued pushes for one
  conversation at once and collapse them on arrival, rather than having been sent one. Same card at
  the end; prove that it is the same card.
- **Wire `onDeletedMessages()`**, which RuStore calls when one or more pushes were **not** delivered
  (TTL expiry being its own example) and for which it recommends syncing with your own server. Given
  that `26-04` sets a deliberately short `ttl`, this is the correct recovery hook for a phone that
  was away: refresh the conversation list rather than leaving the operator with a silent gap. FCM's
  version of this item never named it.
- **A tap opens the thread, never the list** (`navigation.md`'s deep-link table), restoring a sane
  back stack: back from a thread opened by a notification goes to the conversation list, not out of
  the app.
- **The `POST_NOTIFICATIONS` runtime permission** (Android 13+), asked at the moment it means
  something rather than at first launch, and the app still working — and saying what stopped working —
  when it is refused.
- **An honest state when push cannot work on this phone, driven by
  `RuStorePushClient.checkPushAvailability()`.** RuStore Push needs a *distributor* app installed
  (RuStore, or an undisclosed VK fallback elected remotely), RuStore un-restricted in the background,
  and **the operator signed in to a RuStore account** — a longer list than FCM's Play Services, and
  `adr/0180` names it as the finding most likely to change the provider decision. The app says which
  condition is unmet rather than silently never notifying; `onError` gives
  `HostAppNotInstalledException`, `HostAppBackgroundWorkPermissionNotGranted` and
  `UnauthorizedException` to distinguish them, with RuStore's own caveat that the last may not be
  raised even when it applies.
- **Measure the delivery latency, because nothing else in this design can.** RuStore publishes no
  polling interval, no delivery-time target and no priority lever, so `26-01` deliberately makes
  **no latency claim at all** and this item is where one becomes possible. Wall-clock from send to
  notification on a real phone, screen off — **and again with RuStore's background permission
  denied**, since RuStore's own documentation says that case is "significantly" slower without
  saying by how much. Report the numbers and the method per rule 7; if they are bad, say so plainly
  rather than softening them, because `adr/0180` names RuStore's Universal API as the reopening point
  that this measurement is the trigger for.

## Out of scope

- The notification settings screen and its switches (`26-19`).
- Any server-side work (`26-03`, `26-04`, `26-05`).
- A push for a waiting conversation, a team-chat mention, or a calendar booking deadline. `adr/0179`
  names all three as deliberately left out, and the first has **no server-side signal at all** — there
  is no `ConversationStarted` contract to subscribe to.
- The booking deep-link arm of `navigation.md`'s table — there is no booking push to open.

## Done when

- [ ] **A real phone, screen off, receives a push for an assignment and for a visitor message and taps
      through to the right thread** — the item's whole promise, recorded with the date it was
      observed and the device named.
- [ ] A push for the conversation **currently open and visible** is suppressed, and the same push with
      the app backgrounded is not — both proven, because getting this backwards is invisible in one
      direction and infuriating in the other.
- [ ] Four messages in one conversation replace one another rather than stacking four — including
      the case where the phone was **offline while all four were sent** and receives them together,
      which is the case RuStore's missing collapse key makes newly possible.
- [ ] A redelivered push for a message already seen renders nothing new.
- [ ] **Delivery latency is measured and reported**, screen off, with and without RuStore's
      background permission — the number this design currently refuses to assert.
- [ ] `checkPushAvailability()` returning `Unavailable` produces a state the operator can act on,
      naming which condition failed.
- [ ] `onDeletedMessages()` is wired and proven to trigger a refresh.
- [ ] No message body reaches the notification — asserted on the payload the service receives, not on
      the text that happens to be displayed.
- [ ] Denying `POST_NOTIFICATIONS` leaves the app usable and states what it can no longer do.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
