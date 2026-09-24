# 26-86 · A third push kind: someone is waiting

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, by the author, while deciding `26-85`'s own presence model.
- **Depends on**: `26-05`'s fan-out shape (`NotifyOperatorDevicesHandler`), `26-18`'s channel/settings
  machinery, `26-19`'s notification-settings screen.
- **Reopens something `26-18`/`adr/0179` deliberately left out.** Both named "a push for a waiting
  conversation" as out of scope, for a concrete reason: "the first has no server-side signal at all —
  there is no `ConversationStarted` contract to subscribe to." That gap is this item's own first job to
  close, not an assumption to work around.

## What this item is

A third notification kind, alongside the two `26-18` already ships (an assignment, a visitor message
on an assigned conversation): **a visitor's conversation has entered the queue and nothing has claimed
it yet.** One promise: **nobody misses a waiting visitor because their phone was in their pocket.**

## Decided by the author, 2026-09-24 — read before changing any of it

- **Default enabled, for everyone who can see the Диалоги section** — administrator and operator alike.
  The author's own reasoning: the downside of a harmless, occasionally-redundant notification is far
  smaller than the downside of a client sitting unanswered because everyone assumed someone else saw it.
- **Whether a plain Operator (holds `conversation:send` but not `conversation:assign`,
  `ago-chat`'s own `Permission` enum) can even act on this notification is a real, open question the
  author explicitly left unresolved** — such an operator cannot claim a conversation from the queue at
  all today, so the notification may be purely informational for them ("watch how fast people leave the
  queue"), which the author judged "not fatal" rather than something this item has to settle. **Do not
  hide the notification, the toggle, or the «Ожидают» tab from a plain Operator as part of this item** —
  if that turns out to be the wrong call, it is a separate, later item with its own number.
- **A settings toggle, per operator, off is not the default** — the switch exists so someone who finds
  it noisy can turn it off, not so it starts off and has to be discovered.

## Scope

**`ago-chat`** — the missing signal:
- Publish a real event when a conversation is created in `Waiting` state with no operator assigned
  (`StartConversationHandler`'s own commit, or wherever a conversation first becomes visible in the
  queue — read that handler before assuming which point is correct).
- A new `NotifyOperatorDevicesHandler` arm (or a new, adjacent handler — the existing one's own two-arm
  shape is precedent either way) sending to **every** operator on the site who holds `conversation:read`
  for it, not to one assignee — there is no assignee yet. Reuse `PushMessage`'s existing shape;
  `data` carries `conversationId` only, matching the assignment kind's own payload (no domain body,
  same privacy rule `26-18` already established).
- A metrics reason tag for this kind, alongside `"assigned"`/`"message"` — and, since `26-81` already
  flagged that neither existing kind puts its own reason on the wire, **put an explicit `reason` key on
  all three kinds while this item is touching the payload shape anyway** — carries out `26-81` in the
  same change rather than leaving it for a fourth item to rediscover the identical gap.

**`ago-android`** — the receiving half:
- A third `PushNotificationChannel` value (`Waiting`, or similar), created alongside the existing two in
  `PushNotificationChannels.kt`.
- `IncomingPush` gains a third case; `parseIncomingPush` now reads the real `reason` key from the
  server (see above) as its primary discriminator, not the `messageId`-presence inference `26-81`
  documented as fragile.
- A settings row in `NotificationSettingsScreen` (`26-19`'s own screen) — a switch, default on, next to
  the two existing channel rows, following the identical "deep-link to system channel settings, don't
  duplicate the OS's own toggle" pattern those two already use.
- `decideAlert`'s suppression rule does not obviously apply here the same way — there is no single
  "open conversation" a waiting-notification is about the way an assignment or a message is. State
  plainly in the report what suppression rule (if any) was applied and why — a reasonable default is
  "never suppressed by conversation-open state, only by whether the app is in the foreground on the
  Диалоги → Ожидают view already showing it," but confirm against the real `ConversationListViewModel`
  state rather than assuming.

## Out of scope

- Any change to who *can* claim a waiting conversation, or to the «Ожидают» tab's own visibility —
  both explicitly left open above.
- `26-83`'s own still-unsolved periodic-burst investigation, `26-84`/`26-85`'s presence work — this item
  adds a new kind of push, it does not touch when or whether the operator's connection stays alive.

## Done when

- [ ] A new visitor conversation entering `Waiting` produces a real push to every eligible operator on
      the site, proven against a real send (or an honest `[~]` if only provable via `MockEngine`/fake in
      this sandbox, matching this stage's own established pattern).
- [ ] The notification names no message body and no visitor identity beyond what the existing two kinds
      already show.
- [ ] The settings toggle exists, defaults on, and turning it off actually stops the notification.
- [ ] `26-81`'s own gap (no explicit `reason` on the wire) is closed for all three kinds in the same
      change - closing `26-81` itself when this lands.
- [ ] `dotnet format`/`build`/`test` (ago-chat) and `./gradlew ktlintCheck lint test` (ago-android) both
      green.
