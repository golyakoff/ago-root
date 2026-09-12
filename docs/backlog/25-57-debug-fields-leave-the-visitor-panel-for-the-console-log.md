# 25-57 · Debug fields leave the visitor panel for the browser console

- **Stage**: 25
- **Status**: done — `ago-console#204`
- **Verified**: 2026-09-12 — all four fields confirmed real in `ago-console/src/workspace/VisitorPanel.tsx`
  (~lines 121-148): `strings.visitorIdLabel`/`visitorNotInQueue`, `strings.queueConversationStartedTitle`,
  `siteId`, `conversationId`. Re-checked after `25-58`'s merge to this same file — unaffected, different
  region.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

The Посетитель panel shows four fields with no operational use to an operator: ID посетителя
("Не в вашей очереди"), Диалог начат ("Неизвестно"), Сайт UUID, Диалог UUID. The author's own
decision: these are occasionally useful for support/debugging, never for the operator's own
day-to-day work.

## Scope

- Remove all four fields from the visible UI of the Посетитель panel.
- Emit the same information via `console.log` (or an equivalent structured debug log) when the panel
  renders, so it stays reachable via the browser's own DevTools (F12) for a support/debugging session,
  per the author's own instruction.

## Outcome

The `<dl className="ago-aside__facts">` block that rendered all four fields is gone from
`VisitorPanel.tsx`. A `useEffect` keyed on the four primitive values (not the `conversation` object
reference, so an unrelated prop change like `visitorOnline` doesn't re-log it) fires
`console.log("[VisitorPanel] visitor/conversation identity", { visitorId, conversationStartedAt, siteId, conversationId })`
on mount and whenever the identity actually changes. `siteId`/`conversationId` themselves are
untouched — still passed to every child panel exactly as before, only their visible rendering here
is gone. Now-dead CSS (`.ago-aside__facts`, `.ago-aside__id`) removed alongside.

## Done when

- [x] None of the four fields (ID посетителя, Диалог начат, Сайт UUID, Диалог UUID) renders visibly
      in the Посетитель panel.
- [x] The same values are written to the browser console when the panel loads, inspectable via F12.
