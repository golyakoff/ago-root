# 25-185 · The console has no date or time input styling

- **Stage**: 25
- **Status**: done — `ago-console#265` (`56b593d`), `ago-brandbook#6` (`0ece59b`). Independently
  re-verified before merging: `typecheck`/`lint`/`test` (1553/1553, unchanged — correctly, this is
  pure CSS with no new component or behavior) / `ux-gate` (67 passed, 9 skipped) all re-run directly
  for `ago-console`; live browser check in both light and dark theme confirms the native picker icon
  is legible against both (dark glyph on white in light, light glyph on dark surface in dark).
  Deployed and confirmed live: `apply-demo.sh` run, rollout + both migrator jobs completed,
  `curl .../version.json` returns the new commit, `components.html` reachable live,
  `check-manifest-drift.sh` clean.
- **Depends on**: nothing
- **Found**: 2026-09-20, the author, reviewing the brandbook's components page: date input is missing
  today, time input isn't needed yet but should exist in the same style so it's ready when it is.

## What is actually true today

`ago-console/src/components/Input.tsx` is a thin wrapper around a native `<input>` - it forwards
`type` straight through and applies `.ago-control` regardless of what `type` is. `<Input type="date">`
and `<Input type="time">` therefore almost certainly already render with the right border/radius/focus
ring today, simply because nothing in `Input.tsx` special-cases `type`. What's actually missing is
narrower than "a date input component": nobody has used `type="date"`/`type="time"` anywhere yet, so
the native picker icon (the calendar/clock glyph a browser draws inside a date/time input) has never
been checked against `components.css`'s dark theme - a browser's native date/time picker icon has its
own separate rendering path (`::-webkit-calendar-picker-indicator`) that plain `.ago-control` styling
does not touch, and it commonly renders as a *dark* glyph invisible against `--ago-surface`'s own dark
value.

## Goal

- Confirm `<Input type="date">`/`<Input type="time">` render correctly against `.ago-control` as-is -
  most likely no `Input.tsx` change needed at all.
- Style the native picker indicator icon so it's visible in both the console's light and dark themes
  (`::-webkit-calendar-picker-indicator`'s own `filter`/`color-scheme` is the usual fix - check what
  actually renders in both themes before picking one).
- Add both to the brandbook's `components.html` under the existing `Input`/`Field` section, in their
  real states (empty, filled, invalid, disabled) - the identical treatment every other control already
  gets there, in both the light and real dark theme (`25-184`'s own toggle).

## Out of scope

- A custom date/time picker widget - native browser pickers only, this item is about making the
  existing generic `Input` component correctly support these two `type` values, not building a new
  control.
- Any date/time *formatting* or timezone logic - `docs/conventions/date-and-time.md` governs that
  separately and this item touches no business logic at all.
- The phone-number-with-flag input - `25-186`, a separate, larger promise.

## Done when

- [x] `<Input type="date">` and `<Input type="time">` render correctly (border, radius, focus ring,
      invalid/disabled states) via the existing `Input`/`Field` components - confirmed live in a
      browser, not asserted from the code.
- [x] The native picker indicator icon is visible against both the light and dark theme's
      `--ago-surface` - confirmed live in both themes. — fixed via `color-scheme` on `.ago-control`,
      gated by `tokens.css`'s own three-state cascade.
- [x] `components.html` shows both under the Input/Field section in their real states, in both themes.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` green for `ago-console`; local `docker build` +
      browser check for `ago-brandbook`; deployed and confirmed live the same way `25-183`/`25-184`
      were.
