# 25-57 · Debug fields leave the visitor panel for the browser console

- **Stage**: 25
- **Status**: ready
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

## Done when

- [ ] None of the four fields (ID посетителя, Диалог начат, Сайт UUID, Диалог UUID) renders visibly
      in the Посетитель panel.
- [ ] The same values are written to the browser console when the panel loads, inspectable via F12.
