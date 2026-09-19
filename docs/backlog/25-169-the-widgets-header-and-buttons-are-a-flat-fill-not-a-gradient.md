# 25-169 · The widget's header and buttons are a flat accent fill, not a gradient

- **Stage**: 25
- **Status**: ready - one real open question named below, not decided here
- **Found**: 2026-09-19, the author asked for the widget's header and buttons to use a gradient
  dominated by the tenant's own primary color, "as on the landing page", instead of a solid fill.

## What is actually true today

Every accent-colored surface in the widget is a flat, single-color fill of one CSS custom property,
confirmed directly in `ago-widget/src/ui/styles.ts`:

```css
--ago-accent: #2f6fed;   /* default; overridden per-site via ui/appearance.ts's parseWidgetColor */
...
.ago-header { background: var(--ago-accent); }
.ago-message--operator .ago-bubble-content { background: var(--ago-accent); }
.ago-contact-capture-submit, .ago-primitive-form-submit { background: var(--ago-accent); }
```

(and several more sites - `.ago-launcher`, focus outlines, etc. - all reading the same one property).
`--ago-accent` is set once, in `ui/widget.ts`, from `Ago.Chat.Domain.WidgetConfig.PrimaryColorHex` via
`ui/appearance.ts`'s `parseWidgetColor` - **a single hex color, not a pair**. There is no second color
anywhere in this pipeline today.

The landing page's own gradient the author is pointing at (`ago-landing/styles.css`) is built from
**two** fixed brand tokens it already owns:

```css
background-image: linear-gradient(105deg, var(--blue), color-mix(in srgb, var(--blue) 55%, var(--violet)));
```

`ago-landing` can do this because `--blue`/`--violet` are both its own constants. The widget has no
equivalent second color - a tenant configures exactly one `PrimaryColorHex`.

## The one real open question

**How is the gradient's second stop derived from a tenant's single configured color?** Two honest
options, named rather than picked silently:

- **Derive it algorithmically from the one color already known** - e.g. `color-mix(in srgb, var(--ago-accent) <n>%, black)` /
  a fixed hue-rotate, computed once in CSS with no new wire field. Keeps `WidgetConfig` unchanged; the
  gradient is "the tenant's own color, darkened/shifted" rather than "the tenant's own color plus a
  second brand color" - which is a different visual promise than the landing page's own two-brand-color
  gradient, and worth the author confirming that reading is the intent before it is built.
- **Add a second configurable color** (a `PrimaryColorHex`-shaped sibling field) so a tenant can pick
  their own second stop the way they pick the first. Real product-surface growth (`WidgetConfig`, the
  console's own `WidgetConfigPage.tsx`, the wire contract) for what the author's own phrasing
  ("градиент с преобладающим основным цветом", "dominant primary color") suggests is not actually
  wanted - a *derived*, single-color gradient reads as the closer match to what was asked, but this item
  does not decide that unilaterally given it changes the technical shape substantially.

Recommendation, not a decision: the derived (single-input) approach - it matches "dominant primary
color" literally, ships with no wire/console change, and is reversible into the second option later if a
tenant ever wants to pick both stops themselves.

## Scope

- Once the derivation approach is confirmed: change `.ago-header`, `.ago-message--operator .ago-bubble-content`,
  `.ago-contact-capture-submit`/`.ago-primitive-form-submit`, `.ago-launcher`, and any other
  `background: var(--ago-accent)` site in `styles.ts` that reads as a primary surface (not every
  `--ago-accent` use is a fill - some are outlines/text color and should very likely stay flat) to a
  gradient built from `--ago-accent` (and its derived second stop, however that is computed).
- Keep the derived value computed in CSS (a `color-mix`/similar expression referencing `--ago-accent`),
  not duplicated as a second custom property `ui/widget.ts` would need to set - one source of truth for
  the tenant's color, the gradient is a pure function of it.

## Out of scope

- The console's own brand mark or the favicon work (`25-167`, `25-168`) - unrelated surfaces, filed
  separately.
- Any change to what a tenant can configure, unless the second option above is the one chosen.

## Done when

- [ ] The open question above is answered (which derivation, or a second configurable color) before
      implementation starts
- [ ] The widget's header, primary buttons, and operator message bubbles render a gradient dominated by
      the tenant's own primary color, confirmed live against at least two different configured colors
      (not just the default blue)
- [ ] Every existing widget appearance/rendering test that asserts on `--ago-accent`'s own flat value
      still passes or is updated deliberately, not accidentally broken
