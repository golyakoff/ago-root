# 25-206 · Channel-switcher row text gets a fixed dark grey, and the banner gets row dividers

- **Stage**: 25
- **Status**: done — `ago-widget#127`
- **Found**: 2026-09-21, the author, reviewing `25-204`'s hover banner live: the label text still
  read as "unstylish" even after `25-205` removed the brand-colour tint (falling back to
  `color: inherit`, the panel's own near-black). A dedicated Artifact (a real replica of both
  surfaces, with a colour slider) was built to pick the final shade; the author picked **`#374151`**
  after comparing it live against the mobile touch routing sheet's own look.

## Scope, decided by the author directly (not to be second-guessed)

1. **Set the channel row label colour to `#374151`**, a fixed value, not `color: inherit`. Applies to
   both hover-capable surfaces that share `buildChannelSwitcherRow`: the `AboveComposer` banner
   (`25-204`) and the mobile touch routing sheet (`25-197`). The cleanest fix is almost certainly one
   line on the shared base rule (`.ago-channel-switcher-row` in `ui/styles.css`) - confirm the two
   existing colour overrides on more specific rows (`.ago-channel-switcher-row--open-chat`'s
   `var(--ago-accent)`, `.ago-touch-routing-row--cancel`'s `#6b7280`) still win over the new base
   colour by source order once this lands (they are declared after the base rule today - verify this
   stays true, do not assume).
2. **Add horizontal divider lines to the `AboveComposer` banner, matching the mobile touch routing
   sheet's own pattern exactly**: `.ago-touch-routing-row` carries `border-top: 0.0625rem solid
   #e5e7eb` **unconditionally on every row, including the first** - there is no `:first-child`
   exception, so a divider sits between the sheet's own question heading and its first channel row
   too. The banner has no heading, but the same unconditional-divider rule should still apply to
   every one of its rows including the first (a line just under the banner's own top rounded corner)
   - this is a deliberate replication of the mobile sheet's own look, not an oversight to correct.
   Today the banner only has a divider before its final "Онлайн чат" row
   (`.ago-channel-switcher-row--open-chat`'s own `border-top`); add the missing dividers before every
   other row. Avoid a visibly doubled border-top on the "Онлайн чат" row if the general rule already
   covers it (same value, so purely a cleanliness question, not a visual bug either way).
3. **Do not touch icons at all** - the author's own explicit instruction. The colour-picker Artifact
   used simplified, illustrative icon glyphs that do not match this codebase's own real brand icons
   (`buildBrandIcon`/`CHANNEL_ICON_TREES`) or their sizing - those are correct as they are today and
   are not part of this item's scope. Icon size, icon colour, and icon markup in both surfaces stay
   byte-for-byte unchanged.
4. **`BelowLauncher`'s icon-only row** (`buildChannelSwitcherLauncherIcon`) is untouched - it carries
   no text label and no divider today, and this item does not add either.

## Out of scope

- Icon size, icon colour, icon markup - anywhere.
- `BelowLauncher`'s own layout.
- Font-size unification between the two surfaces - not asked for here (the touch sheet's `16px` vs.
  the banner's inherited size were both shown side by side in the picker Artifact for visual
  reference only, not because the author asked to unify them - if genuinely still open, it is a
  separate question, not this item's).

## Done when

- [x] A connected channel's row label (Telegram, WhatsApp, Vk, Max) reads `#374151` in both the
      `AboveComposer` banner and the mobile touch routing sheet.
- [x] The "Онлайн чат" row's accent colour and the touch sheet's "Отмена" row's own grey are provably
      unaffected (still their own deliberate colours, not `#374151`).
- [x] The `AboveComposer` banner shows a divider line above every row, including the first, matching
      the touch routing sheet's own unconditional-border pattern - confirmed live, not only in a unit
      test (screenshot or a real-browser `getComputedStyle` check).
- [x] No icon (size, colour, or markup) changed anywhere, in either surface.
- [x] Existing tests updated to the new colour/divider expectations, not deleted to dodge them.
- [x] `npm run typecheck`/`lint`/`test`/`ux-gate` all green.

## Outcome

Landed as `ago-widget#127`. `.ago-channel-switcher-row`'s `color: inherit` became a fixed `#374151`;
the new `.ago-channel-switcher-banner .ago-channel-switcher-row { border-top: 0.0625rem solid
#e5e7eb; }` rule adds the missing dividers to the banner (two-class specificity correctly beats the
"Онлайн чат" row's own single-class override, so its pre-existing identical border is now redundant
rather than conflicting). No icon touched anywhere.

Verified independently: `npm run typecheck`/`lint` clean; `npm test` 532/532 (43 files); `npm run
build` 38.6 KB gzipped (budget 46 KB); `npm run ux-gate` 16/16. Reviewed the diff directly - the CSS
change is exactly the two lines the scope called for, plus a well-reasoned doc comment. CI green on
the PR before merge.
