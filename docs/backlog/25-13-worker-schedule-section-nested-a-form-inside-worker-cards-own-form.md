# 25-13 · `WorkerScheduleSection`'s form was nested inside `WorkerCard`'s own form

- **Status**: done — `ago-console#178` (`be3e1c3`), redeployed to `ago-demo`
- **Date found**: 2026-09-08, the author testing the worked example live
- **Filed after the fact**: the fix was diagnosed and merged the same day it was found, during a live
  debugging session, without a backlog file being written first — this file settles that gap rather
  than leaving the mirror issue (`ago-root#778`) open with nothing behind it.

## What was actually happening

Clicking "Создать расписание" inside a worker's expanded "Изменить" panel did a full page
navigation (`GET /calendar/masters?`) instead of reaching the save API — reported by the author as
"страница перезагружается полностью, не сохраняя ничего в network", confirmed live via the browser
pane's own accessibility tree and `read_network_requests`, and cross-checked against a HAR export.

**Root cause**: `CalendarWorkersPage.tsx` renders `WorkerScheduleSection` as `WorkerCard`'s own
`children`, and `WorkerCard.tsx` renders `children` inside its own `<form onSubmit={...}>`.
`WorkerScheduleSection`'s root element was *also* a `<form>` — two nested `<form>` elements in the
live DOM, which is invalid HTML. A real browser resolves that by falling back to native form
submission on the inner button's click instead of running React's `onSubmit`, which is exactly the
"full reload, nothing in network" symptom.

**jsdom does not reproduce this.** The test suite's own fails-before proof could not be "submitting
the inner form navigates away", because jsdom does not carry the real nested-form navigation
fallback. The honest fails-before proof is structural instead: asserting there is only ever one
`<form>` on the page while the schedule section is open.

## Fix

`WorkerScheduleSection.tsx`'s root element became a `<div>`; its submit button became a plain
`<Button type="button" onClick={...}>` instead of `<Button type="submit">`. A documented consequence:
`required`/`min` HTML attributes on the schedule fields no longer trigger native browser validation,
so the server's own `catch`/`calendarErrorMessage` is the only validation surface left — stated in
code as a comment rather than left to be rediscovered.

## Done when

- [x] Editing a worker never puts two `<form>` elements on the page at once, asserted by a test that
      fails against the pre-fix code (`CalendarWorkersPage.test.tsx`).
- [x] Creating a schedule from the expanded panel reaches the save API instead of reloading the page —
      verified live in the browser pane against `office.reserve-me.ru` before the fix, and confirmed
      fixed after `ago-console#178` merged.
- [x] Redeployed to `ago-demo` (settled in this same change, alongside `25-11`, `25-12`, `25-09`, all
      of which had also merged to `main` without yet reaching the live console image).
