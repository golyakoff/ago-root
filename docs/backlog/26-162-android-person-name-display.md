# 26-162 · [android] Operator app shows the visitor's name from the Person (adr/0184 S4-android)

- **Stage**: 26 — ADR-0184 (option B) front-end. Design:
  `docs/design/26-134-person-identity-implementation.md` (S4 android half). Backend landed + deployed.
- **Status**: done — merged ago-android#136 (0d73233), build-test + instrumented-tests green. NOT a
  no-op: the premise check found a real regression the deployed calendar `95ce462` introduced (it
  renamed `ContactResponse.CustomerId`→`PersonId` and dropped the name fields), which would have
  broken the Android calendar-backed screens (Клиенты/Утверждены) against the live backend. Fixed by a
  new `PersonsApi` client (chat `GET /api/v1/persons?ids=`) + display-merge with graceful fallback.
  `ConversationSummary`'s own name path was confirmed unaffected. Android ships via RuStore/FCM (not a
  node deploy) — picked up in the next release build.

## One promise
The Android operator app displays a conversation's person consistently with chat as the Person owner
(no calendar customer copy), or is confirmed already correct with the reason recorded.

## Scope
- Investigate `ConversationSummary` / thread header name sourcing against the ADR-0184 final backend.
- If a change is needed: source the display name from the Person (chat API), keep the emoji-pair
  fallback (26-116); new strings as resources both languages (no literals).
- **androidTest landmine**: any composable a shell/back-contract test reaches must not call
  `hiltViewModel()` under plain `ComponentActivity` — keep VM construction lazy/route-default.

## Done when
- [x] Change landed green: `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin`
      BUILD SUCCESSFUL (KtorPersonsApi 9, ContactsViewModel 16, ConfirmedBookingsViewModel 12,
      KtorBookingsApi 36). No new user-facing strings. Fixed a real regression, not a no-op.
