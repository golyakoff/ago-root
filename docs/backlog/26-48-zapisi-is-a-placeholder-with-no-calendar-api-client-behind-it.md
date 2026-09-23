# 26-48 · Записи is a placeholder, and there is no calendar API client behind it

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console`'s calendar surface and `ago-android`'s own
  `scope-inventory.md` against `ago-android` `main` at `b099282`, with the approved mockup Artifact
  ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) §04 for the screen itself.

## Found

The mockup's §04 calls Записи «вторая причина носить его с собой», and it is the one claim in that
document with a mechanism behind it: a booking auto-confirms unless somebody vetoes it before its
deadline, so being away from a desk has a cost that a phone removes. The destination exists in the
bottom bar today and shows one sentence saying it is not built.

The screen is not the only thing missing. **This app has no way to reach AGO Calendar at all.**

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:50-55` is the whole destination —
  a title and `bookings_placeholder_body`. It is wired at
  `app/src/main/kotlin/ago/chat/android/shell/AppShellScreen.kt:283`.
- The permission gate already exists and is already right:
  `core/domain/.../navigation/BottomDestination.kt:49-67` draws Записи for `calendar:configure` **or**
  any of `booking:confirm`/`reject`/`cancel` **or** `customer:read`, the identical four-way gate
  `ago-console/src/shell/consoleNav.ts:311-320` applies in its own operator branch. Nothing in this
  item touches that.
- **There is exactly one API base URL in the app.** `app/build.gradle.kts:148` declares
  `AGO_API_BASE_URL` and nothing else; `app/src/main/kotlin/ago/chat/android/di/AppModule.kt:87`
  carries it into `config.apiBaseUrl`, and every one of the four API classes
  (`KtorIdentityApi`, `KtorOperatorPermissionsApi`, `KtorConversationsApi`, `OperatorHubConnection`)
  is constructed from that single value (`AppModule.kt:120,139,156,178`). The console has a **second**
  one — `config.calendarApiBaseUrl`, which `CalendarQueuePage.tsx:92,157-164` treats as genuinely
  optional ("calendar not configured" is a real rendered state). Android has no counterpart, no
  `:core:domain` port for bookings, and no `:core:network` adapter.
- What the queue actually is, server-side: `GET` through
  `ago-console/src/api/calendarApi.ts:639` (`getPendingBookings`), returning
  `Ago.Calendar.Contracts.PendingBookingResponse`
  (`ago-calendar/src/Ago.Calendar.Contracts/ConsoleContracts.cs:134-146`) — one queue spanning every
  calendar the tenant has, with no "mine" (`CalendarQueuePage.tsx:45-47`).

## Scope

One promise: **Записи shows this tenant's real pending-booking queue, read-only.**

1. **A second base URL**, declared the way the first one is (`build.gradle.kts:148`'s own
   `agoProperty` shape) and carried through `AgoConfig`/`AppModule` alongside `apiBaseUrl`. It is
   **nullable/absent-tolerant**, because the console's own is — a deployment without AGO Calendar is a
   real state, and the destination must render "not configured" rather than fail, matching
   `CalendarQueuePage.tsx:157-164`.
2. **A `BookingsApi` port in `:core:domain`** and a `KtorBookingsApi` adapter in `:core:network`,
   built exactly the way `ConversationsApi`/`KtorConversationsApi` are — the whole status-code-to-
   meaning mapping in the adapter, a sealed result type in the port, no Ktor type crossing the
   boundary. The `X-Ago-Active-Site` and bearer plugins are already installed on the shared client
   (`installAgoRestDefaults`); this adapter inherits both rather than threading either by hand.
3. **The Ожидают tab replaces the placeholder** — the mockup's segmented control («Ожидают ·
   счётчик» / «Утверждены» / «Клиенты») with only its first segment doing anything, and the other two
   drawn but leading nowhere is **not** acceptable: draw only the segments that have a screen, the
   same rule `MoreScreen`'s own `buildMoreRows` already applies (`MoreScreen.kt:138-143`).
4. **The row is the mockup's card** — service and duration, when and with whom, the deadline as
   «Подтвердится через N ч», and the calendar's short id. What it can honestly say today is limited:
   see Out of scope.

## Out of scope

- **Every write.** Отклонить/Отменить are `26-49`. A read-only queue is a complete promise on its own
  — an operator who can see that something is waiting and how long it has can at least call somebody.
- **The names the mockup draws on those cards.** `PendingBookingResponse` carries `WorkerId`,
  `ServiceId` and `CalendarId` and no name for any of them — `26-50` is the item that fixes the wire.
  Until it lands, this screen renders the short ids the way this app already renders every identifier
  (`IdentifierText`), never a fabricated label.
- **Утверждены (`26-51`), Клиенты (`26-52`), and the whole Конфигурация записей hub.** The hub is six
  preconditions across seven console routes (`scope-inventory.md` §4) and is nobody's first slice.
- `canSeeBookings` and the bottom-bar gate. Already correct, already tested
  (`BottomDestinationTest`).

## Done when

- [ ] An operator holding any of the four gate permissions opens Записи and sees the tenant's real
      pending bookings, oldest deadline first.
- [ ] A deployment with no calendar base URL configured renders a stated "not configured" message, not
      a spinner and not a crash.
- [ ] A failure to read the queue renders as a refusal with a retry, and never as a raw exception
      class name (`26-59` states that rule for the whole app; this new adapter must be born obeying it
      rather than adding a fifth copy of `describe()`).
- [ ] No name is invented for a worker, service or calendar anywhere on the screen.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device against a tenant with at least one pending booking, in both light and
      dark.
