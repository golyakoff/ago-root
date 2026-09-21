# 26-18 · Receiving, rendering and suppressing a push

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the second half of the Android client item
  `docs/architecture/push-notifications.md` names at its foot; `26-06` is the first. Split on
  promises per rule 15: *the server knows about this device* and *the phone buzzes correctly* are
  separately true or false, and each lands green on its own.
- **Verified**: 2026-09-21 — `ago-console/src/workspace/alerts.ts` and `useAlerts.ts` exist and are
  the rules being ported; `adr/0179` §3 is the decision that the server never suppresses on presence
  and that **each client decides whether to be loud**. The collapse key and the client-side dedupe are
  `26-05`'s own stated idempotency mechanism, with this item owning the client half of both.
- **Depends on**: `26-06` (a registered device), `26-15` (a thread to open on a tap), and — for the
  end-to-end proof — `26-04` and `26-05`. Before those land, a data message can be sent to a known
  token by hand from the Firebase console; say which path was used for each Done-when box.

## What this item is

A push arrives on a real phone, is rendered or deliberately silenced by the same rule the console
already applies, and tapping it lands on the right thread. One promise: **the operator learns a
visitor is waiting while the phone is in their pocket** — which is `plan.md`'s stated reason this app
exists at all.

## Scope

- **`FirebaseMessagingService` handling data-only messages, never `notification` payloads.** A
  `notification` payload is rendered by the Android system with no app code running, which would throw
  away the whole suppression decision below. `adr/0179` names the two costs of data-only and accepts
  them: they need `android: { priority: "high" }` to escape Doze promptly, and a force-stopped app
  receives nothing at all (Android's rule, not a design choice).
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
- **The collapse key / notification tag `ago-conversation-{conversationId}`**, matching
  `useAlerts.ts`'s own `Notification` tag exactly — a visitor sending four messages replaces its own
  card rather than stacking four — **plus client-side dedupe by `MessageId`**. Together those are the
  idempotency `26-05` deliberately has no inbox row for, and this item owns the half that runs on the
  phone.
- **A tap opens the thread, never the list** (`navigation.md`'s deep-link table), restoring a sane
  back stack: back from a thread opened by a notification goes to the conversation list, not out of
  the app.
- **The `POST_NOTIFICATIONS` runtime permission** (Android 13+), asked at the moment it means
  something rather than at first launch, and the app still working — and saying what stopped working —
  when it is refused.
- **An honest state when Google Play Services is absent.** FCM does not exist without it, and
  `adr/0179` names this as a real product risk in this deployment's own market rather than a solved
  problem. The app says so rather than silently never notifying.

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
- [ ] Four messages in one conversation replace one another rather than stacking four.
- [ ] A redelivered push for a message already seen renders nothing new.
- [ ] No message body reaches the notification — asserted on the payload the service receives, not on
      the text that happens to be displayed.
- [ ] Denying `POST_NOTIFICATIONS` leaves the app usable and states what it can no longer do.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
