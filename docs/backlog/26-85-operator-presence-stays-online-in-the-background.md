# 26-85 · An Operator stays online in the background, the way the phone itself is always reachable

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-24, by the author, live on the demo stand, investigating `26-84`.
- **Depends on**: `26-06`/`26-18`/`26-19` (push, done), `26-84` (the mechanism this item exists to fix
  the consequence of).
- **Decided by the author, 2026-09-24**: the product's own model is that a phone is "at hand" without
  needing its screen on — an operator should count as reachable because a push can wake them, the same
  way a clock or a fitness tracker app stays alive in the background via its own persistent
  notification. This item keeps that model rather than accepting `26-84`'s alternative of loosening the
  server-side disconnect-grace policy.

## What is actually true today, confirmed against real code and real data (see `26-84` in full)

- `OperatorHubConnection` (`ago-android`) deliberately disconnects its SignalR socket on every
  backgrounding, by design, and does **not** reconnect until the app is foregrounded again — its own
  doc comment states this in these words: "Android will suspend a background socket… the app connects
  when it is in front and lets go when it is not."
- `OperatorDisconnectGraceConsumer` (`ago-chat`) releases every conversation an operator holds back to
  the queue once they have had zero live connections for 30 seconds straight.
- Confirmed live: a real assignment ended 23 seconds after being taken; the disconnect-grace queue sat
  saturated at its 50-message prefetch ceiling for over 20 minutes during one short test session.

## What this item is

**Keep the operator's hub connection alive while the app is backgrounded**, the standard Android
pattern for an app that needs continuous connectivity while not on screen — a foreground service with
its own persistent, low-priority notification, the same mechanism a call, a music player, or a
navigation app already uses to survive backgrounding.

## Scope

- **A new foreground `Service`** (e.g. `OperatorPresenceService`) that owns `OperatorHubConnection`'s
  lifecycle independently of any `Activity`/Compose lifecycle — started when the signed-in identity
  holds the ability to answer conversations (see the gating rule below) and stopped on sign-out.
- **Gated by `Permission.ConversationSend`, not merely "signed in."** `ago-chat`'s own `Permission` enum
  (`Ago.Chat.Domain/Permission.cs`) already distinguishes `ConversationSend` (reply to a conversation)
  from `ConversationAssign` (claim one from the queue) — a role holding neither (a pure administrator
  with no operator seat) has no conversation to be pushed about and must not run this service.
  `ago-android`'s `OperatorPermissionsApi.fetchMyPermissions()` already fetches the granted permission
  set (`GET /api/v1/operators/me`) — check for `"conversation:send"` in that set, the real wire string,
  not a guessed name.
- **`android:foregroundServiceType="connectedDevice"`**, declared on the service in the manifest —
  Android 14+ requires one of a fixed set of types; "maintains a connection to a remote system" is what
  this service actually does, and omitting the declaration is a hard manifest-merger/runtime failure on
  API 34+, not a style choice.
- **Its own notification channel**, `IMPORTANCE_LOW` (silent, no sound, no heads-up) — distinct from the
  two push channels `26-18` already created. Suggested text: title "AGO Chat", body naming that the app
  is staying online for incoming conversations — the author's own call on exact wording; a neutral,
  short line is enough, not a marketing sentence.
- **Request `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** at the point it means something (after sign-in, once
  this service is about to start) — without it, several OEM battery managers (and stock Doze under
  some conditions) can still throttle or kill a foreground service's own network activity despite the
  platform's documented guarantees. Ask once; if refused, the app must still work — falling back to
  today's behavior (disconnect on background, rely on push and reconnect-on-foreground) rather than
  crashing or nagging repeatedly.
- **Confirm `OperatorDisconnectGraceConsumer`'s 30-second grace period needs no server-side change** —
  if the socket now genuinely survives ordinary backgrounding, that timer starts doing exactly the job
  its own doc comment describes (a real, sustained loss of connectivity), not a spurious one. Say so
  explicitly in the report, backed by a real backgrounded-for-over-a-minute test that does *not* lose
  the assignment.

## Out of scope

- Changing `26-84`'s server-side grace period or release mechanism — this item is the client-side fix
  `26-84`'s own options list named as the chosen direction; no `ago-chat` change is expected unless the
  real-device test below proves the socket still cannot survive backgrounding even with a foreground
  service (state this plainly if it happens, rather than silently patching the server too).
- A settings toggle to disable this — the author's own decision above is "always on by default for an
  answering operator"; if a toggle turns out to be wanted later, that is a new item, not a quiet
  addition here.
- Anything about `26-83` (the periodic push-send burst) — a separate, still-unsolved investigation.

## Done when

- [ ] A real phone, screen off, app backgrounded for over a minute, still shows a live connection in
      the server's own connection registry — proven directly (the same check this session used to find
      the problem), not inferred from the notification being present.
- [ ] An assignment taken before backgrounding is still held after backgrounding for over a minute —
      proven against real `conversation_assignments` rows, the same table this session read to find the
      bug.
- [ ] The foreground service does not start for an identity holding no `conversation:send` permission.
- [ ] Battery-optimization exemption is requested once, at a meaningful moment, and the app remains
      functional (falls back gracefully) if refused.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
