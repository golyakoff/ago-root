# 26-118 · [android] A swipe-deleted conversation must vanish from the list at once, not linger as «Стирается…»

- **Stage**: 26.
- **Status**: ready — queued (author asked to file it and take it into the work queue, 2026-09-25).
- **Found**: 2026-09-25, by the author on a real phone: after swiping a conversation to delete, the row
  stays in the Диалоги list showing a «Стирается…» state (see screenshot) instead of disappearing.

## What is actually true today

Swiping a conversation to delete marks it «Стирается…» and leaves the row visible in the list while the
backend deletion runs. The author's point: the intent is already expressed by the swipe — the row should
**disappear from the interface immediately** (optimistic removal), and the actual erasure can finish in the
background afterwards. A lingering «Стирается…» row is clutter for an action the user already committed to.

## Scope

- On swipe-to-delete, **remove the row from the list immediately** (optimistic update) — no «Стирается…»
  placeholder occupying a slot.
- The real deletion continues in the background.
- **On failure, restore the row** (re-insert it where it was) and surface a non-blocking error (a snackbar
  with «Не удалось удалить», ideally with «Повторить») — optimistic removal must be reversible if the
  backend rejects it, so a failed delete does not silently lose a conversation from view.
- If an undo window is desired instead of/in addition (a brief «Отменить» snackbar before the request
  fires), note it — but the baseline requirement is: the row leaves the list at once.
- Remove the now-unused «Стирается…» string/state if nothing else uses it (or keep it only for the failure
  path if that reads better — decide and say which).

## Out of scope

- The Bookings/Записи screens (26-117) and any other list.
- Changing the backend deletion itself.

## Done when

- [ ] A swiped conversation disappears from the list immediately; no «Стирается…» row remains.
- [ ] A failed background deletion restores the row and shows a recoverable error.
- [ ] Strings are resources (ru + en). `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin`
      green; a test proves optimistic removal + restore-on-failure; counts reported.
