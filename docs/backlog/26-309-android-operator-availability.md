# 26-309 — Operator availability («Отошёл»/«Онлайн») on Android + presence indicator

**Status:** design (this document is the deliverable; no code in this item)
**Author trigger:** the quiet-hours-vs-green-dot question. The account-avatar dot on Android is
*connection*-only today; the author's instinct was that the dot should reflect **away**, and that the
app should let an operator step away the way the web console already can. This designs the indicator
semantics, the control, the hub wiring, the quiet-hours relationship, and the slices to file.

Follows the Android-parity memory ("the app must let tenant-admins do everything the console does"):
the console has an away control (`AwayControl.tsx`, `23-20`); the app must too.

---

## 0. Premises checked against source (2026-09-30, fetch+ff on all four repos first)

**The server model is real and complete — no `ago-chat` change is expected.** Confirmed:

- `Ago.Chat.Domain/OperatorStatus.cs` — `enum { Offline, Online, Away }`.
- `Ago.Chat.Domain/Operator.cs:122` `GoOnline()` (unconditional — the "I'm back" action);
  `:139` `NoteConnected()` (passive connect: `Offline → Online` only, **leaves a deliberate `Away`
  alone**); `GoAway()`, `GoOffline()`.
- `Ago.Chat.Api/Hubs/OperatorHub.cs:369` `SetAwayAsync(bool away)` — `true` → `GoAwayAsync`,
  `false` → `GoOnlineAsync`. **Returns `void`** (a `Task`).
- `OperatorHub.cs:389` `GetMyPresenceAsync()` — **returns `bool`** (`status == OperatorStatus.Away`).
  Not the enum: the wire contract is a single "am I away" bit.
- `OperatorHub.cs:96` `OnConnectedAsync` calls `NoteConnected` (not `GoOnline`) on every connect and
  reconnect — this is the `23-20` subtlety that makes **`Away` survive a socket blip**.
- `OperatorHub.cs:116` `OnDisconnectedAsync` calls `GoOffline` only when the *last* connection is gone,
  and `Operator.GoOffline` (`23-20`) leaves a deliberate `Away` intact.
- Neither `SetAwayAsync` nor `GetMyPresenceAsync` has a permission check, by construction: the
  `OperatorId` comes from the connection's own JWT, so "an operator cannot set another's presence" holds
  without a resource to guard (`SetOperatorPresenceHandler` doc comment). The app inherits that for free.

**No server push for the operator's *own* availability.** The console never subscribes to its own
away-state; it *polls* `GetMyPresenceAsync` once on every "connected" transition
(`OperatorConnectionProvider.tsx:153`). There is no `MyPresenceChanged` hub callback. The app must do
the same: read on (re)connect, and otherwise trust its own last write. (`OperatorPresenceLost` is a
*visitor/queue*-facing broker event about a *different* operator's connection dropping — not a self
signal, and not consumed by the app.)

**The console deliberately did NOT fold away into its connection badge.** `AwayControl.tsx`'s doc
comment is explicit: the connection badge answers "is the socket up", away answers "is the person
here", and "folding 'away' into that badge as a sixth label would answer a different question with the
same widget and reintroduce the exact confusion". This is the two-meanings caveat this item must
weigh — see §1.

**The Android app today:**

- `core/network/.../OperatorHubConnection.kt:83` states in so many words: *"What this class
  deliberately still does not do: `SetAwayAsync`/presence — no backlog item has reached it yet."*
- The dot: `HubConnectionDot.kt` (`colorFor`/`labelFor`, `internal`) and `AccountAvatarAction.kt`
  (the account-menu avatar with the corner dot). Both map `OperatorHubConnectionState`
  (`Connected`/`Connecting`/`Reconnecting`/`Disconnected`) to a colour + a spoken
  `"Соединение: <state>"` description. Four states, three colours.
- `hubConnectionState` is a **plain value threaded** from `MainActivity` → `SignInViewModel`
  (`hubConnectionState = hubConnection.state`, `SignInViewModel.kt:67`) → `SignInHost` → `AppShellRoute`
  → every tab → each tab's `AccountAvatarAction`. No screen owns a connection.
- `SignInViewModel` injects the concrete `OperatorHubConnection` and already exposes its `state`.
- Colour tokens available: `AgoLive` (status green, `Color.kt:81`), `agoStatusColors().warning`
  (a true amber — `AgoStatusColors.kt`, Material 3 has no warning role), `agoStatusColors().dangerText`
  (red), `MaterialTheme.colorScheme.tertiary` (today's connecting/reconnecting neutral).
- `26-19`'s away-note already exists on `NotificationSettingsScreen.kt:238` and says away
  *«Управлять им с этого экрана нельзя»* ("can't be managed from this screen"). Once this item ships a
  control, that note is misleading and must be updated in the same slice (see §4).
- `OperatorPresenceService` (`26-85`) keeps the hub *connected* in the background — this is
  **connection** presence, an unrelated axis, despite the name collision. It does not set `Away`.

---

## 1. Indicator semantics — the decision

**Recommendation: (a) fold availability into the existing account-avatar dot, with a documented
priority — but under a single honest meaning that dissolves the console's two-meanings objection.**

### The unifying meaning

The dot answers exactly one question, in plain words: **"can a visitor reach me right now?"**

- **Green** — connected **and** Online: yes, I am receiving visitors.
- **Amber (warning)** — connected but **Away**: no, I have stepped away (assignment engine requires
  `Online`, so an `Away` operator is excluded exactly as a disconnected one is).
- **Amber-neutral (tertiary)** — Connecting / Reconnecting: trying; not yet reachable.
- **Red** — Disconnected: no, the link is down.

Under this reading, `Away` and `Disconnected` are not "two different questions on one widget"; they are
two causes of the *same* operationally-visible fact — **not currently assignable**. The server itself
treats them identically for assignment (`Status == Online`, never "not Offline"). So one dot stating
"reachable / not reachable" is honest, not overloaded.

### Why this overcomes the console's caveat rather than ignoring it

The console's objection was made in its own context, and that context differs on three counts:

1. The console's connection badge carries **five** labels (`ui-inventory.md` §3.1) — a rich connection
   story. Android's dot is nearly one bit, in a 10 dp corner of a 36 dp avatar. There is no room for a
   second control with a persistent `Alert` banner beside it (the console's chosen shape), and the
   author explicitly does not want one — they asked why the *dot* isn't green/red.
2. The console keeps a separate, always-visible `AwayControl` with a persistent `Alert` while away —
   its honesty guarantee. Android keeps honesty differently: the dot *speaks* its state
   (`contentDescription`), and the account menu names the availability in words and is where the toggle
   lives (§2). The active-away fact is never hidden behind colour alone.
3. Distinct hue. The two amber-ish states use genuinely different roles — `tertiary` (a neutral/bluish
   "trying") for connection-in-flight vs `warning` (a saturated amber/orange) for Away — so a glance
   distinguishes them and the label removes any doubt.

**The trade-off, stated honestly:** a fold means a non-green dot has more than one possible cause, and a
purely-colour reader (glance, colour-blindness) learns only "not reachable", not *why*. We accept that:
"not reachable" is the actionable bit, and the "why" is one tap away in the menu, spoken by the dot, and
distinguished by hue. The rejected alternative (b) — a second chip beside the dot — buys per-cause
glanceability at the cost of app-bar space the author rejected and a second widget every top-level
screen's header would have to place, for a distinction the menu already makes precisely.

### Combined-state table (exact colour + spoken label)

Priority is strict: **connection trouble outranks availability**, because while the socket is not up the
server-side availability is unknowable and must not be asserted. `isAway` only paints the dot once the
state is `Connected`.

| Connection state | `isAway` | Dot colour | Spoken `contentDescription` (RU) | (EN) |
|---|---|---|---|---|
| `Connected` | `false` | `AgoLive` (green) | «Онлайн» | "Online" |
| `Connected` | `true` | `agoStatusColors().warning` (amber) | «Отошёл» | "Away" |
| `Connecting` | any | `colorScheme.tertiary` | «Соединение: Подключение…» | "Connection: Connecting…" |
| `Reconnecting` | any | `colorScheme.tertiary` | «Соединение: Переподключение…» | "Connection: Reconnecting…" |
| `Disconnected` | any | `agoStatusColors().dangerText` (red) | «Соединение: Отключено» | "Connection: Disconnected" |

Notes:

- When **connected**, the availability is the headline the dot speaks («Онлайн»/«Отошёл») — because
  connection is fine and no longer the interesting fact. When **not connected**, the connection is the
  headline (unchanged wording, so the existing screen-reader contract for those three states is
  preserved verbatim — see the test note in §6).
- Green is reserved for the all-clear (`Connected && !isAway`). This is a deliberate tightening: a green
  dot now means "a visitor can reach me", which is *more* honest than today's "the socket is up".

---

## 2. The «Отошёл / Онлайн» control

**Placement: a row inside the account-menu dropdown (`AccountAvatarAction`), directly under the
name/email header, above «Настройки».** This mirrors the console putting `AwayControl` in the workspace
rail (a persistent operator-scoped control), adapted to the app's one operator-scoped surface — the
account menu — which already exists on every top-level screen and already owns the dot the control
governs. It keeps the toggle beside the very indicator it changes.

### Behaviour and states

- The row shows the **current** availability and the action to flip it, mirroring `AwayControl`'s
  `isAway ? come-back : go-away` shape:
  - when Online → action «Отойти» (go away), with a caption naming the effect on the visitor;
  - when Away → action «Вернуться» (come back), and a persistent visible marker that away is active
    (the amber dot already is that marker; the menu row restates it in words so the effect is never
    colour-only — the console's `Alert` honesty rule, adapted).
- **Disabled while not `Connected`.** `SetAwayAsync` is a hub invoke; with no live socket it cannot
  land. Disable the row (and say why succinctly) whenever `hubConnectionState != Connected`, so the
  control never lies about a click that could not have reached the server. This mirrors
  `OperatorHubConnection.sendMessage`'s own `NotConnected` guard.
- **Pending** while the invoke is in flight (disable, don't optimistic-flip). Update the shown state
  **only after the server confirms**, exactly as the console does
  (`OperatorConnectionProvider.tsx:191` — "an optimistic update here would show a control that already
  claims a state a failed call never actually reached").
- **Error** surfaced, not swallowed (a control whose click did nothing and says nothing is the failure
  `23-20` exists to fix). A brief inline error line / snackbar; the menu stays open.

### Copy (RU default `values/`, EN `values-en/`)

Every string names the effect on the visitor, never a bare "Away"/"Online" (the console's rule — a
label alone repeats the problem in a smaller font). Proposed keys:

| key | RU (`values/`) | EN (`values-en/`) |
|---|---|---|
| `account_availability_online_label` | «Онлайн» | "Online" |
| `account_availability_away_label` | «Отошёл» | "Away" |
| `account_availability_go_away_action` | «Отойти» | "Step away" |
| `account_availability_come_back_action` | «Вернуться» | "I'm back" |
| `account_availability_go_away_detail` | «Новые диалоги вам назначаться не будут» | "New chats won't be assigned to you" |
| `account_availability_come_back_detail` | «Снова получать новые диалоги» | "Start receiving new chats again" |
| `account_availability_active_notice` | «Вы отошли — новые диалоги не назначаются» | "You're away — new chats aren't being assigned" |
| `account_availability_unavailable_note` | «Управление статусом доступно при активном соединении» | "Status can be changed while connected" |
| `account_availability_toggle_error` | «Не удалось изменить статус» | "Couldn't change your status" |

(Exact wording is the author's to tune; the shape and the "name the visitor effect" rule are the
design commitment.)

---

## 3. Hub wiring

### 3.1 New methods on the hub client — no `ago-chat` change

Add two methods to `OperatorHubConnection` (`:core:network`), mirroring the console's
`operatorConnection.ts:441/451` and every other method in the file (fixed arity, awaited invoke):

```kotlin
// SetAwayAsync(bool away) — true = GoAway, false = GoOnline. No return value.
public override suspend fun setAway(away: Boolean) {
    requireConnection().invoke(SET_AWAY_METHOD, away).await()
}

// GetMyPresenceAsync() -> bool (true == Away). Boxed Boolean for the deserialiser, the same
// Int::class.javaObjectType reasoning sendMessage already documents.
public override suspend fun getMyPresence(): Boolean =
    requireConnection().invoke(Boolean::class.javaObjectType, GET_MY_PRESENCE_METHOD).await()
```

with method-name constants `"SetAwayAsync"` / `"GetMyPresenceAsync"`. Both belong on an **interface**,
not just the concrete class, for the same testability reason every other hub method already is
(`OperatorHubEvents`/`HubConnectionControl` doc comments): the state holder that calls them must be
unit-testable against a plain fake with no `com.microsoft.signalr` socket.

**Placement decision (teaching-mode):** these are a *read* (`getMyPresence`) and a *write*
(`setAway`) of operator presence, not connection lifecycle and not message events. Cleanest home is a
new small interface `OperatorPresenceControl` (methods `getMyPresence`, `setAway`) that
`OperatorHubConnection` also implements and `di/AppModule` binds as one more view onto the same
`@Singleton` (the exact "one extra `@Provides`, not a second connection" shape
`provideOperatorHubEvents` already uses). The alternative — widening `HubConnectionControl`
(currently connect/disconnect only) — would conflate "manage the socket" with "set the person's
status", the same conflation §1 rejects for the dot; and calling SignalR from a ViewModel directly
would put `com.microsoft.signalr` on `:app`'s classpath and break the "screens do not own connections"
boundary.

### 3.2 Where the availability state lives, and how it is threaded

Put it beside `hubConnectionState`, in `SignInViewModel` (it already injects the connection and already
exposes `hubConnection.state`):

- expose `availability: StateFlow<Boolean>` (or a tiny `OperatorAvailability` type — but a `Boolean
  isAway` is honest and matches the wire; YAGNI says start there);
- a coroutine that **observes `hubConnection.state`** and, on every transition **into `Connected`**,
  calls `getMyPresence()` and publishes the result — the console's "re-read on every connected, initial
  and reconnect alike" rule (`OperatorConnectionProvider.tsx:147`). Logged-not-fatal on failure (a
  stale bit for one cycle is cosmetic; the next connected re-read fixes it);
- a `setAway(away)` action that calls the hub and, **on success only**, updates the `StateFlow`.

Then thread `isAway` down **exactly like `hubConnectionState`**: `MainActivity` →
`SignInHost`/`AppShellRoute` → each tab → `AccountAvatarAction`, as a plain value with a `false`
default. `AccountAvatarAction` (and `HubConnectionDot`, if any caller wants the bare dot to reflect it)
gains one parameter, `isAway: Boolean`, and `colorFor`/`labelFor` take the pair
`(OperatorHubConnectionState, isAway)` and apply the §1 table.

**Teaching-mode (Compose state / layering):** availability is app-wide session state that reads from
the one `@Singleton` connection, so it lives once in the session-scoped `SignInViewModel`, not in a
per-screen ViewModel. The alternative — each screen's own ViewModel reading `getMyPresence` — would
duplicate the read, risk N re-reads per reconnect, and let two screens disagree. Threading it as a
plain parameter (rather than a `CompositionLocal` or a screen-level inject) keeps every top-level
screen and `AccountAvatarAction` **stateless and test-drivable with a fixed value**, the identical
split the app already uses for `hubConnectionState`, `permissions`, and the unread counts.

### 3.3 Reconnection behaviour (confirmed against `ago-chat`)

- **`Away` persists across a socket drop.** `OnConnectedAsync` calls `NoteConnected`, not `GoOnline`, so
  a reconnect never silently clears a deliberate `Away` (`Operator.NoteConnected` doc comment, the whole
  point of `23-20`). The app's re-read on reconnect therefore returns the still-`Away` value and the dot
  stays amber — correct.
- **On last-connection loss the server marks the operator `Offline`** *unless* they were deliberately
  `Away`, in which case `Away` is kept. Either way the app is disconnected at that moment, so the dot
  shows the **connection** state (amber-neutral/red) — availability is not asserted while the link is
  down, per the §1 priority. When the link returns, the re-read re-establishes truth.
- **Background presence (`26-85`) is orthogonal.** `OperatorPresenceService` may hold the hub connected
  while the app is backgrounded; that keeps the operator `Online` and receiving, and an explicit `Away`
  set from the menu still overrides it server-side. No coupling needed; note the name collision so a
  future reader does not conflate the two "presence" concepts.

---

## 4. Quiet-hours ↔ Away

**Recommendation: NO coupling. Quiet hours stays client-only push suppression (`adr/0179`).**

Quiet hours suppresses *local notification loudness* on this one device (`QuietHours.kt`,
`suppressesAt`); it is deliberately never sent to the server. `Away` is a *server* state that stops
assignment for the operator across *all* their devices and tells the *visitor* something. Auto-setting
`Away` during quiet hours would:

- send a device-local, timezone-bearing schedule's effect to the server — exactly the leak `adr/0179`
  ("What this design deliberately leaves out") and `26-19`'s Scope refused;
- change what visitors see based on one phone's clock, even while the operator is actively answering
  from the web console.

The two axes are answering different questions for different audiences. Keep them decoupled.

**Rejected alternative (recorded):** an opt-in toggle «в тихие часы автоматически ставить Отошёл». If
the author ever wants it, note that it would still just call `setAway` (the server API), introducing no
*new* quiet-hours-to-server channel — but it co-mingles a device-local schedule with a cross-device
status and re-opens the timezone question `adr/0179` closed. Not now; file separately if wanted.

**Required copy fix in this item:** `NotificationSettingsScreen.kt`'s `26-19` away-note
(`notification_settings_away_note`) currently states away *«Управлять им с этого экрана нельзя»*. Once
the control ships, update it to point at the account menu (e.g. *«…изменить его можно в меню
аккаунта»*), in **both** language files, in the slice that adds the control (docs/copy are part of the
deliverable). The note's other half — that away is per-operator, not per-device, and shared with the
console — stays true and stays.

---

## 5. Slice plan (rule 15), files, and the ADR judgement

Two slices, each **one promise that lands green**, neither leaving the other red. Split on differing
promises (observe vs control), not on code separability.

### Slice 1 — «the account dot reflects availability» (observe)

*Promise:* when the server says the operator is Away, the account-avatar dot shows amber and speaks
«Отошёл»; when Online, green «Онлайн»; connection-trouble states are unchanged.

- `core/network/.../OperatorHubConnection.kt` — add `getMyPresence()` + method-name constant;
  new `OperatorPresenceControl` interface (read half), implemented by the connection.
- `app/.../di/AppModule.kt` — bind `OperatorPresenceControl` to the singleton.
- `app/.../signin/SignInViewModel.kt` — `availability: StateFlow<Boolean>`, driven by the
  observe-state-and-re-read-on-connected coroutine.
- `app/.../MainActivity.kt`, `SignInHost`, `shell/AppShellRoute`+`AppShellScreen`+`AppShellContent`
  and each tab host (`ConversationsTabHost`, `BookingsScreen`, `MoreScreen`, `AnalyticsTabHost`,
  `TeamRoute`) — thread `isAway` down beside `hubConnectionState`.
- `app/.../ui/components/HubConnectionDot.kt` — `colorFor`/`labelFor` take `(state, isAway)`; apply
  the §1 table; add the `warning`/green mapping.
- `app/.../ui/components/AccountAvatarAction.kt` — new `isAway` param, passed into the dot.
- Strings: `account_availability_online_label`, `account_availability_away_label` (both languages).
- Tests: `OperatorHubConnectionTest` (getMyPresence arity/invoke), a `SignInViewModel` unit test with a
  fake `OperatorPresenceControl` (re-reads on connected; keeps last value otherwise), and the
  instrumented `AccountAvatarActionTest`/`HubConnectionDot` assertions updated for the new
  connected-state wording (see §6).

### Slice 2 — «the operator can step away from the account menu» (control)

*Promise:* the account menu offers Отойти/Вернуться; tapping it sets the server status and the dot
follows.

- `core/network/.../OperatorHubConnection.kt` — add `setAway(away)` + constant; extend
  `OperatorPresenceControl` (write half).
- `app/.../signin/SignInViewModel.kt` — `setAway` action (update state on success only), threaded to
  the menu as a lambda (beside `onOpenSettings`/`onSignOut`).
- `app/.../ui/components/AccountAvatarAction.kt` — the availability row (states: current/pending/
  disabled-while-not-connected/error), between header and «Настройки».
- `app/.../devices/NotificationSettingsScreen.kt` + strings — update the `26-19` away-note (§4), both
  languages; add the §2 control strings, both languages.
- Tests: `SignInViewModel` setAway (success flips state; failure leaves it and surfaces error);
  instrumented `AccountAvatarActionTest` — row visible, disabled when `Disconnected`, toggles the
  lambda, pending/error rendering.

### ADR judgement

**No new ADR; this document is the record, plus a one-line code pointer.** Folding two axes into one
dot is genuinely "worth arguing about" (the console argued the opposite), which is why the reasoning is
captured here in full and why `colorFor`/`labelFor` should carry a short comment citing this doc so a
future reader does not "restore" a separate chip on the strength of `AwayControl`'s comment. But it is a
single-repo, product-surface UI-composition choice, not a cross-cutting platform guarantee or a
weakened invariant — the bar an ADR meets. `adr/0179` already owns the quiet-hours decoupling, which §4
only reaffirms. If the author would rather have the divergence-from-console decision as a first-class
ADR, that is a one-line change to this plan — flagged as an open question.

---

## 6. Implementation cautions (call these out in every worker brief)

- **`compileDebugAndroidTestKotlin` is a separate CI gate.** `AccountAvatarAction` gains a required
  `isAway` param and (slice 2) a `setAway` lambda; `colorFor`/`labelFor` change signature. Every caller
  in `app/src/main` *and* every `androidTest`/`test` call site must be updated or the instrumented
  compile fails green-looking unit runs. Grep `AccountAvatarAction(`, `colorFor(`, `labelFor(`,
  `HubConnectionDot(` before trusting a build.
- **Instrumented tests assert the UI, and the last three Android changes each hit a stale-assertion
  instrumented failure.** Specifically `AccountAvatarActionTest.thePresenceDotStillSpeaksItsConnectionState`
  asserts `contentDescription("Соединение: Отключено")` (Disconnected — **preserved** by this design)
  but the class's `render()` default is `Connected`, whose spoken description **changes** from
  «Соединение: Подключено» to «Онлайн»/«Отошёл». Any test that reads the connected-state description
  must be updated in lockstep. Add explicit new-state assertions rather than leaving the old ones to
  rot.
- **Strings in both languages, resources only.** `values/` is RU (default), `values-en/` is EN. No new
  literal strings anywhere (the post-`26-91` rule). Every §2/§4 key in both files.
- **Don't call a green dot "healthy" on plumbing alone.** Verify on a real device / emulator that
  setting away from the menu turns the dot amber *and* that the web console reflects the same operator
  as away (cross-surface truth — the whole point of a server-side status), and that reconnecting keeps
  away amber.

---

## 7. Open questions for the author

1. **The fold vs a separate chip (§1).** Recommendation is (a) fold, under the "can a visitor reach me"
   meaning. Confirm you want the dot itself to carry away (your original instinct), accepting that a
   non-green dot's cause is read from the label/menu, not the colour alone.
2. **Amber for Away.** Recommended `agoStatusColors().warning` (a saturated amber) to distinguish it
   from the `tertiary` connecting/reconnecting tone. OK, or do you want a different hue for Away?
3. **Control home (§2).** Account-menu row is the recommendation. Acceptable, or would you prefer it on
   a settings screen (further from the dot it governs)?
4. **Copy.** The §2 strings name the visitor effect; tune wording as you like.
5. **ADR (§5).** Design-doc-plus-code-comment, or do you want a first-class ADR for the
   diverge-from-console decision?
