# 26-13 · The operator hub connection

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the second third of `plan.md`'s Phase 0: "the SignalR operator hub over a
  connection Android will suspend". Named there as one of the three things most likely to be wrong,
  and the one with the least in common with anything either existing client had to solve.
- **Verified**: 2026-09-21 — `ago-console/src/realtime/calendarOperatorConnection.ts:57-108` holds the
  token-factory shape being ported and its own comment naming the `5-16` reason (the factory reads a
  ref on every negotiate rather than capturing a token). `ago-android/docs/architecture.md` §Realtime
  carries the three properties below; `adr/0178` §"The realtime half" records why Microsoft's Java
  client is the choice and what it costs.
- **Depends on**: `26-12`.

## What this item is

The app holds one live `/hubs/operator` connection that survives token expiry, network loss and the
app being backgrounded — and screens observe it rather than own it. One promise: **the transport
works**, proven before a single conversation is rendered through it.

## Scope

- **One connection per signed-in session**, owned by a single connection holder in `:core:network` and
  exposed as a Kotlin `Flow`. **Screens do not own connections** (`architecture.md`) — a screen that
  opens its own is the shape that produces two connections after a rotation.
- **`com.microsoft.signalr:signalr`, Microsoft's official Java client.** What it replaces: a
  hand-rolled SignalR protocol over Ktor's WebSocket — real, unestimated work. `adr/0178` already
  recorded that this library's JVM-only-ness is the single hardest constraint on ever sharing this
  layer with iOS, and accepted it with eyes open; do not re-litigate it here.
- **An access-token factory that re-reads the current token on every negotiate**, never one captured
  at construction. Both existing clients reached this bug independently, and the console's own file
  says so in a comment.
- **The active-site query-string parameter** on the connection — the hub's equivalent of the REST
  header `26-12` installed, because a query string is how the server reads it there
  (`architecture.md` §Tenancy).
- **Reconnect with the client's own backoff and full jitter**, and **on reconnect re-read history from
  the last known `sequence`** rather than trusting what was in memory when the socket dropped.
- **Ordering comes from the server-assigned `sequence`, never from a timestamp**, and is guaranteed
  per conversation and never globally (`CLAUDE.md` rule 6). Anything the holder sorts, sorts by that.
- **Lifecycle tied to the app being in the foreground.** Android will suspend a background socket;
  that is not a tuning problem and no amount of Kotlin fixes it (`plan.md`). The app connects when it
  is in front and lets go when it is not — which is precisely why push exists as a separate mechanism.
- **A connection-state surface good enough to prove this item** — a debug row or a banner, not a
  designed screen.
- **Never add a parameter to an existing hub method.** `realtime.md`: a hub method's parameter count
  is a contract and may never change — learned through two live outages. The client calls what exists,
  and if something is missing it is a backend item, not a client workaround.

## Out of scope

- Rendering any conversation (`26-14`, `26-15`).
- Push (`26-06`, `26-18`) — the whole reason this connection is allowed to go away when the app does.
- Presence and the Away control. When they land, `SetAwayAsync` is **per operator, not per
  connection** — setting Away on the phone sets it for the desktop console too — and the screen must
  say so rather than invent a per-device variant (`architecture.md`). Not this item's to build.
- Team chat's own hub traffic.

## Done when

- [ ] The app holds a live hub connection against a real `Ago.Chat.Api` and **survives the access
      token expiring** — proven by waiting out the realm's own five-minute lifetime, or by shortening
      it deliberately for the test; say which was done.
- [ ] Killing the network and restoring it reconnects, and the backoff is jittered — asserted on the
      computed delay sequence, not on observed wall-clock timing.
- [ ] After a reconnect, history is re-read from the last `sequence`: a message sent while
      disconnected appears exactly once, neither missing nor doubled.
- [ ] Backgrounding and foregrounding the app leaves **exactly one** connection — proven by a
      server-visible count or by the holder's own state, not by the absence of a visible symptom.
- [ ] Rotating the device does not drop or duplicate the connection.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
