# 26-162 · [android] Operator app shows the visitor's name from the Person (adr/0184 S4-android)

- **Stage**: 26 — ADR-0184 (option B) front-end. Design:
  `docs/design/26-134-person-identity-implementation.md` (S4 android half). Backend landed + deployed.
- **Status**: ready — **verify the premise first** (background-worker-brief §0.6): confirm what the
  Android operator app actually needs. It already reads `ConversationSummary` (visitorName +
  emoji-pair fallback) from chat's API; ADR-0184 keeps that shape. Establish whether any real change
  is needed (e.g. surfacing a person name for calendar-origin conversations) or whether this is a
  no-op / small adjustment, and say so plainly rather than inventing work.

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
- [ ] Either the change lands green, or the item is closed with a recorded reason that no change is
      needed. If landing: `JAVA_HOME=<jdk-17-adoptium>` `./gradlew ktlintCheck lint test
      :app:compileDebugAndroidTestKotlin` green; strings both languages.
