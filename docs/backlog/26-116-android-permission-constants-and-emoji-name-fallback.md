# 26-116 · [android] Permission constants + localized emoji-name fallback dictionary

- **Stage**: 26 — implementation of `26-111` (design: `docs/design/26-111-thread-contact-detail-panel.md`).
- **Status**: done — merged as `ago-android#110` (Permission constants + emoji-pair name fallback, ru/en).
- **Depends on**: nothing. Lands early; the contact panel's per-element permission gating and the
  emoji-pair name fallback both build on it.

## What and why

The contact-detail panel gates elements by permission (hide, don't disable) and, where a visitor has no
real name, shows a **localized emoji-pair fallback** rather than a raw hex code. Both are small,
self-contained foundations that the later panel tickets depend on. Kept as its own ticket so it is
file-disjoint from `26-115`'s data clients (no `AppModule` edit here) and can run a parallel lane.

## Scope

- The `Permission` constants the panel needs (whatever the panel gates on — confirm against the design's
  §7 gating list and the existing `core/domain/.../permissions/Permission.kt`); add only what is missing.
- A **localized emoji-pair name fallback** helper: given a visitor's emoji-pair identity, render a
  human-readable localized name (both `ru` and `en` string resources — CLAUDE.md "Android strings must be
  resources"), following the curated avatar-emoji categories already used in the app. This is the fallback
  the app uses when there is no real contact name — **never a raw hex/shortId on screen** (26-111 decision:
  name is plain text; a missing name falls back to this, not to the code).
- Unit tests for the fallback mapping (a known pair → its localized name, both locales).

## Out of scope

- The data clients (`26-115`), the bottom-sheet UI, the write actions.
- Name assessment / «Недействительно» — dropped (26-111 decision #1).

## Done when

- [x] Permission constants present; emoji-pair localized fallback helper with `ru`+`en` resources; never a
      hex code as a fallback.
- [x] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; fallback unit tests pass,
      counts reported.
