# 25-50 · Left menu cleanup and calendar section renames

- **Stage**: 25
- **Status**: done — `ago-console#199`
- **Verified**: 2026-09-12 — `navSectionsAriaLabel` ("Разделы консоли") confirmed real: used as an
  invisible `aria-label` on the desktop rail (`AppShell.tsx:566`), but rendered as a visible `<h2>`
  title inside the mobile drawer (`Dialog.tsx:92-93`, passed via `AppShell.tsx:543`) — exactly the
  "not visible on desktop, visible on mobile" the item describes. `navSectionCalendar`/
  `navCalendarBookings`/`navCalendarQueue` all confirmed real in `consoleNav.ts`/`ru.ts`/`en.ts`.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

`ago-console`'s left menu (`consoleNav.ts`) today: shows a "Разделы консоли" heading; child-item
font size is smaller than top-level items; the Calendar section is labelled "Календарь" and its
confirmed-bookings sub-item is labelled "Записи" (`navCalendarQueue`="В ожидании",
`navCalendarBookings`="Записи").

## Scope

- Remove the "Разделы консоли" heading text entirely — it is not shown anywhere else in either
  mobile or desktop layout.
- Increase child (sub-item) menu font size to match top-level items.
- Rename: the Calendar section's own top-level label "Календарь" → "Записи"; its own confirmed-
  bookings sub-item "Записи" → "Утверждённые". (This is a two-way relabel, confirmed against the
  author's own literal wording — not a typo to "fix" back.)
- Reorder top-level menu items: **Диалоги**, **Записи** (the renamed Calendar section), then every
  remaining item in its current relative order.

## Where this is likely to go wrong

- **This item does not touch `25-51`'s own unread-count badges** — that is real state/behavior and
  its own item, even though it lands on the same menu structure this item reorders and relabels.
  Land this one first; `25-51` reads whatever final menu shape this item leaves.

## Done when

- [x] "Разделы консоли" text is gone from the left menu in every layout. (`ago-console`
      `src/shell/AppShell.tsx`/`src/components/Dialog.tsx`: the mobile drawer's `Dialog` now passes
      `visuallyHiddenTitle`, so the same `<h2>`/`aria-labelledby` pair a screen reader needs is kept,
      classed `.ago-visually-hidden` instead of `.ago-dialog__title` — nothing visible left, on
      mobile or desktop.)
- [x] Child menu items render at the same font size as top-level items. (`src/shell/shell.css`:
      `.ago-shell__rail-link`/`.ago-shell__drawer-link` now use `--ago-text-base`, matching
      `.ago-shell__rail-section`/`.ago-shell__drawer-section`.)
- [x] Calendar section reads "Записи" (was "Календарь"); its confirmed-bookings sub-item reads
      "Утверждённые" (was "Записи") — routes/behavior unchanged, labels only. (`src/i18n/ru.ts`/
      `en.ts`: `navSectionCalendar` → "Записи"/"Bookings", `navCalendarBookings` →
      "Утверждённые"/"Confirmed".)
- [x] Menu order is Диалоги, Записи, then the rest unchanged. (`src/shell/consoleNav.ts`:
      `buildTenantNavSections`'s own `sections` array moves `calendar` to second place; every other
      section keeps its previous relative order.)

## Outcome

Implemented in the `ago-console` worktree at `fix/25-50-left-menu-cleanup-and-calendar-renames`
(`C:/git/ago/ago-console-25-50`), not yet committed/pushed. Full verification green:
`npm run typecheck` (clean), `npm run lint` (clean), `npm test` (1175 passed / 111 files, up from
1160 passed / 15 failed before the expected test updates below), `npm run build` (succeeds; the
pre-existing >500kB chunk-size warning is unrelated to this item).

Judgment calls:
- **Accessible drawer title (scope item 1)**: added a new optional `visuallyHiddenTitle` prop to
  `Dialog` rather than making `title` optional — `aria-labelledby` needs a real heading to point at
  for every caller, and an optional `title` would leave it dangling for one that omits it. The prop
  swaps the `<h2>`'s class between `.ago-dialog__title` (visible, the other ten `Dialog` consumers'
  default) and the codebase's existing `.ago-visually-hidden` (used already by `Table.tsx`'s caption
  and `Spinner.tsx`'s label). `AppShell`'s mobile drawer is the only caller that passes it. Also
  removed `.ago-dialog--drawer .ago-dialog__title` from `components.css` as dead CSS, since the
  drawer is the only `variant="drawer"` `Dialog` consumer and its `<h2>` no longer takes that class.
- **English label for the renamed Calendar section (scope item 3)**: chose "Bookings" for
  `navSectionCalendar` (was "Calendar") to match "Записи" — the section is not a calendar view, it
  is the tenant's own bookings (waiting queue, confirmed list, contacts, setup). `navCalendarBookings`
  (was "Bookings") became "Confirmed" to match "Утверждённые", freed by the section label taking
  "Bookings" for itself, and reads correctly as the `CalendarBookingsPage`'s own `<h1>` (it *is* the
  confirmed-bookings screen).
- Fifteen existing tests (`src/auth/permissionGating.test.tsx`, `src/i18n/consoleLocale.test.tsx`,
  `src/owner/ownerSitesPage.test.tsx`) asserted the old labels and/or the old section order — updated
  in place, as this item's own text anticipated. A stray doc-comment mention of "Календарь" in
  `ux-gate/fixtures/screens.ts` was also corrected for accuracy, not because any check reads it.
