# 26-126 · [android + mockup] Chat glyph → rounded-rectangle `chat_bubble`; mirror the phone glyph

- **Stage**: 26 — global icon polish (app + the mockup Artifact).
- **Status**: ready — author-directed.
- **Found**: 2026-09-25.

## Changes

1. **Dialogs / chat glyph** — replace the current round chat bubble with the rounded-rectangle Material
   Symbols `chat_bubble` (FILL@0). Change it **everywhere** it appears: the bottom-nav «Диалоги» tab (the
   screenshot), the Записи row chat affordance, and any other use of the chat glyph (`AgoIcons.Chat` and
   its `#i-chat` sprite twin). Update the glyph in `AgoIcons.kt` once so every call site follows.
2. **Phone glyph** — mirror it horizontally (flip across the vertical axis). The stock handset points as
   if the handset sits on the LEFT; in our rows the phone icon is on the RIGHT, so it should point
   "under the right hand". Apply the flip to `AgoIcons.Call` (e.g. a horizontal scale of -1, or a
   mirrored path).

## Also in the mockup Artifact
Apply BOTH changes in the Android mockup Artifact (`#i-chat` sprite → rounded-rectangle path; `#i-call`
mirrored) so future mockups don't regress to the old glyphs.

## Done when
- [ ] The chat glyph is the rounded-rectangle `chat_bubble` in the bottom nav and every other use; the
      phone glyph is mirrored. Both changed in one place (`AgoIcons.kt`) so all call sites follow.
- [ ] The mockup Artifact uses the same two glyphs.
- [ ] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green (incl. the `AgoIconsTest`
      path checks); counts reported.
