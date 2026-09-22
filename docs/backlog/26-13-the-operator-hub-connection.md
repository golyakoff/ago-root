# 26-13 · The operator hub connection

- **Stage**: 26
- **Status**: done — `ago-android#18`; remainder carried out to `26-22`
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

- [~] The app holds a live hub connection against a real `Ago.Chat.Api` and **survives the access
      token expiring** — **carried out to `26-22`**: no real authenticated session exists in this
      environment to hold a real, expiring token against. The token-factory half (re-reading fresh on
      every negotiate, never captured) is proven at the unit level (`HubAccessTokenSingleTest`).
- [x] Killing the network and restoring it reconnects, and the backoff is jittered — asserted on the
      computed delay sequence, not on observed wall-clock timing. `HubReconnectBackoffTest` proves the
      exact deterministic sequence and cap saturation; cross-checked independently against
      `ago-console`'s own `backoff.ts` formula - exact match. The real-network half of this box (an
      actual kill/restore against a live connection) is **carried to `26-22`** alongside the token-
      expiry proof, since both need the same real session.
- [x] After a reconnect, history is re-read from the last `sequence`: a message sent while
      disconnected appears exactly once, neither missing nor doubled. `MessageSubscriptionTest` proves
      this directly and dependency-free (no hub connection needed) - the real end-to-end version
      against a live hub is **carried to `26-22`**.
- [~] Backgrounding and foregrounding the app leaves **exactly one** connection — **carried to `26-22`**
      for the server-visible proof. Structurally proven here: `OperatorHubConnection` is a `@Singleton`
      and `ensureConnection()` builds the underlying `HubConnection` at most once
      (`OperatorHubConnectionTest`), so a rotation or a background/foreground cycle - which recreate the
      `Activity`/`ViewModel` but never this singleton - can only ever call `connect()` on a connection
      that already exists.
- [x] Rotating the device does not drop or duplicate the connection - proven structurally by the same
      "built at most once" singleton property above, and exercised live on the emulator (rotation
      cycled with no crash, no exception in logcat) - though with no real connection active to observe
      surviving the rotation, since no authenticated session exists in this environment.
- [x] `./gradlew ktlintCheck lint test` green; counts reported. 78 tests (25 new), 0 failures; ktlint
      clean.

## Outcome

Landed as `ago-android#18`. `OperatorHubConnection` (`:core:network`, `@Singleton`) is the one
`/hubs/operator` connection for the app's whole signed-in session, exposed as `state`/`messages`
Flows - no screen builds or owns a connection. Wires in Microsoft's Java SignalR client (`adr/0178`),
the identical `5-16` token-freshness discipline `26-12` already proved for the REST client, and the
active-site value as a query-string parameter.

**A real, load-bearing finding, independently re-verified by decompiling the actual jar**:
`com.microsoft.signalr:signalr` 9.0.5 has no automatic-reconnect API at all - no
`withAutomaticReconnect`, no `RetryPolicy`, no `onreconnecting`/`onreconnected`; `HubConnectionState`
has exactly three values (`CONNECTED`/`CONNECTING`/`DISCONNECTED`). Confirmed myself via `javap` on
the real downloaded `signalr-9.0.5.jar` - both `HubConnection`'s and `HttpHubConnectionBuilder`'s
complete public method lists contain nothing reconnect-shaped, only `onClosed`. This is a genuine
capability gap between Microsoft's own JS and Java SignalR clients from the same vendor, not an
oversight in this implementation - the reconnect/backoff loop is hand-rolled from `onClosed` using
the identical full-jitter formula (independently cross-checked against the real
`ago-console/src/realtime/backoff.ts` source - exact match on the arithmetic and the 1000ms/30000ms
defaults) both existing web clients already use.

Verified independently, beyond the implementing worker's own report: re-ran `ktlintCheck`/`lint`/
`test`/`assembleDebug` myself, green; confirmed all 78 tests from the real JUnit XML (25 new); read
`OperatorHubConnection.kt`/`HubReconnectBackoff.kt` line by line.

**Four boxes carried out to `26-22`** (widened the same day to cover this item's own remainder
alongside `26-12`'s): all four need a real, authenticated hub session against the live API, which
this environment could not obtain (no test operator identity exists yet).
