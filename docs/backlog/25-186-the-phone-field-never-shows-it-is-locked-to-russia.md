# 25-186 · The phone field never shows it is locked to Russia

- **Stage**: 25
- **Status**: done — `ago-console#264` (`42effb3`), `ago-widget#109` (`09eb127`), `ago-brandbook#5`
  (`30d06b3`). Independently re-verified by the managing session before merging: `Field.tsx` and its
  existing `adornment` caller confirmed untouched by diff, `PhoneInput.tsx`'s CSS diffed against the
  copy landed in `ago-brandbook`, a live browser check in both light and dark theme (empty/filled/
  invalid states all render correctly; the 🇷🇺 flag emoji renders as literal "RU" text in this
  environment - a known cross-platform flag-emoji limitation, not a defect, and the accepted trade-off
  of choosing emoji over an SVG asset). Full command sets re-run directly: `ago-console`
  typecheck/lint/test/ux-gate (1553 tests, 67 passed/9 skipped), `ago-widget` typecheck/lint/test
  (484 tests) plus an independent bundle-size re-measurement (45.4 KB gzipped, matching exactly).
  **Test coverage gap caught and fixed before merging**: the first pass added zero new tests (same
  1544/482 counts as before) - sent back to add `PhoneInput.test.tsx`, `ContactDetailsPanel.test.tsx`
  additions, and a `contactCapture.test.ts` regression check proving the mask still fires with the
  input nested inside the new wrapper. Deployed and confirmed live on the brandbook side:
  `apply-demo.sh` run, rollout + both migrator jobs completed, `curl .../version.json` returns the new
  commit, `components.html` reachable live, `check-manifest-drift.sh` clean.
- **Depends on**: nothing (independent of `25-185`)
- **Found**: 2026-09-20, the author, reviewing the brandbook's components page and asking for a
  phone-number-input-with-flag control in the style of `react-phone-number-input` - scoped down to a
  single, real gap once the actual code was checked rather than built from the library's own feature
  set.

## What is actually true today

`ago-widget/src/ui/contactCapture.ts`'s phone field is a plain `<input type="tel">` with a hand-rolled
live `+7` mask (`phoneFormat.ts`, `25-28`). That file's own header comment already explains, in detail,
why it is hand-rolled rather than `libphonenumber-js`: the library's metadata-bearing builds cost tens
of KB gzipped even for a single country, against this widget's own hard 45 KB ceiling (now 46 KB per
`25-173`'s own finding, with roughly 0.5 KB of headroom left) - `ADR-0162`'s hand-rolled-ZIP-writer
precedent, restated for phone masking. The mask already assumes Russia and already has an escape hatch
(typing an explicit `+<other-country-code>` bypasses RU shaping entirely, capped at E.164's 15-digit
maximum) - **the number is already, functionally, locked to Russia by default**. What's missing is
purely visual: nothing shows a visitor *that* the field expects a Russian number before they start
typing, the way `react-phone-number-input`'s own flag+prefix does.

`ago-console`'s `Field` component already has an `adornment` slot (`FieldProps.adornment`, "rendered
beside the control on the same row" - the hex-colour swatch on `WidgetConfigPage` is its only caller
today), but it renders **after** the control (`control, then adornment`, `Field.tsx`'s own JSX order) -
this item needs the flag+prefix **before** the control, so it does not fit `adornment` as it exists
today.

## Goal, decided with the author - nothing left to guess

**One real control, reused everywhere a phone number is collected** - not a brandbook-only decoration:

1. A new small presentational piece (`ago-console`'s side, e.g. `PhoneInput.tsx`, wrapping the existing
   `Input`) that renders a flag emoji + dialing code **to the left** of the field, non-interactive (no
   country dropdown - there is exactly one country, so a selector would be doing nothing real):
   `🇷🇺` + `+7`, then the native input for the subscriber digits only. Emoji, not an SVG/icon-font flag -
   costs nothing in bundle size and renders correctly with system emoji fonts everywhere already in use
   (no new asset, no new font).
2. Because this needs the prefix *before* the control and `Field`'s existing `adornment` slot renders
   *after* it, **do not reorder `Field`'s existing adornment for every caller** (that would change the
   hex-swatch field's own layout too, out of scope and unreviewed). Build the flag+prefix inside the new
   component's own markup instead, styled to sit inline-left of the `Input` it wraps - a self-contained
   control, not a change to the shared `Field` component's behaviour. (If, once built, reusing/extending
   `Field` genuinely turns out simpler than a standalone wrapper, that's an implementation judgment call,
   not a re-litigation of this scope - either way nothing about `Field`'s existing callers may change
   shape.)
3. **Real replacement, not just documentation**: `ago-widget/src/ui/contactCapture.ts`'s existing phone
   field gets the same visual treatment (flag + `+7` prefix, drawn in the widget's own vanilla-DOM
   style - it has no React, so this is a parallel small piece of markup/CSS there, not a shared React
   component import). The existing `phoneFormat.ts` masking logic is unchanged - this item is additive
   visual chrome in front of an unchanged input, not a rewrite of the masking. Check `ago-console`'s own
   forms (`CalendarContactsPage.tsx`/`CalendarBookingsPage.tsx` and any other phone-collecting form) for
   the same plain, un-flagged phone field and apply the new component there too if a real one exists -
   confirm what's actually there before assuming a page needs it.
4. Shown on the brandbook's `components.html` in its real states (empty, filled, invalid) - the same
   treatment every other control gets there.

## Out of scope

- Any second country, a working country selector, or `libphonenumber-js`/any phone-parsing library -
  `phoneFormat.ts`'s own header comment already gives the bundle-size reasoning this item does not
  re-litigate; Russia is not a placeholder for "the first of many", it is the whole scope.
- Changing `phoneFormat.ts`'s masking behaviour - this item is the missing visual affordance in front
  of it, not a rewrite.
- The date/time input styling - `25-185`, a separate, unrelated promise.
- Reordering `Field`'s existing `adornment` slot for its current caller(s).

## Done when

- [x] A new phone-input-with-flag piece exists in `ago-console` (wrapping `Input`, flag+`+7` to the
      left, non-interactive), used by every real console form that collects a phone number - confirmed
      against the actual current forms, not assumed. — every candidate page checked; the one real
      editable, un-flagged phone field found was `ContactDetailsPanel.tsx`'s Phone-row edit control
      (every other phone-shaped field on this platform is display-only, masked + Reveal button).
- [x] `ago-widget/src/ui/contactCapture.ts`'s phone field shows the identical flag+prefix treatment,
      `phoneFormat.ts`'s masking behaviour otherwise unchanged - confirmed with a real browser check,
      existing phone-format tests still green. — plus a new regression test proving the mask still
      fires with the input nested one level deeper inside the new wrapper.
- [x] `components.html` shows the new control in its real states (empty/filled/invalid), in both
      themes (`25-184`). — verified live in both themes by the managing session.
- [x] `ago-widget`'s bundle-size budget check still passes - a bare emoji costs effectively nothing, but
      confirm rather than assume given how little headroom `25-173`'s own finding left (~0.5 KB before
      this item, budget already raised to 46 KB). — 45.4 KB gzipped, 0.6 KB headroom left under 46 KB.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` green for `ago-console`; `npm run typecheck`/`lint`/
      `test` green for `ago-widget`; local `docker build` + browser check for `ago-brandbook`; deployed
      and confirmed live the same way `25-183`/`25-184` were. — all re-run independently, see Status.
