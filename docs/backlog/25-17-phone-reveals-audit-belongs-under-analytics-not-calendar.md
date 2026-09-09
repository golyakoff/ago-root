# 25-17 · The phone-reveals audit trail belongs under Analytics, not Calendar

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing — corrects `25-12`'s own nav ordering, landed the same week
- **Found**: 2026-09-09, the author using the console

## What is actually true

`25-12` placed "Показы телефонов" (`CalendarPhoneRevealsPage`) inside the Calendar nav section,
alongside the setup dictionaries, because it is gated on `calendar:configure`. Gating and grouping are
different questions: a tenant reading the nav looks for an audit trail of *who saw what* under
Analytics, not under Calendar's own operational/setup items — it is where "Мои показатели" and the
other analytics screens already live, and it is where this one reads naturally beside them.

## Scope

- Move the `/calendar/phone-reveals` nav entry from `buildCalendarItems` to `buildAnalyticsItems`
  (`ago-console/src/shell/consoleNav.ts`). The gate stays `calendar:configure` — only the section it
  appears under moves, not who can see it.
- The route itself (`/calendar/phone-reveals`) does not need to move; only the nav placement does,
  unless leaving the URL under `/calendar/` while the nav lives under Analytics reads as confusing
  once it is actually looked at — if so, say so and decide.

## Done when

- [ ] "Показы телефонов" appears under Analytics in the console nav, gated on `calendar:configure`
      exactly as before.
- [ ] `consoleNav.test.ts` and `permissionGating.test.tsx` (both touched by `25-12`) are updated to
      match the new section.
