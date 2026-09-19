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

## A reference example, and the gradient model read off it

The author showed a competitor's widget header as a "this looks good" reference (not reproduced here -
described structurally instead, since the useful part is the technique, not the specific pixels). It is
**not** a plain two-stop linear gradient across the whole surface. It is two layered pieces:

1. A **near-flat dark base** - the header's own background reads as a single deep, desaturated tone
   (not an obvious left-to-right/top-to-bottom blend by itself).
2. A **soft radial accent blob anchored in one corner** (top-right in the reference), a brighter,
   saturated color fading to transparent within roughly the near half of the panel - the only part of
   the surface that actually looks like "a gradient" to the eye.

That is a different, and arguably more distinctive, model than "the tenant's one color, lightened at one
end" - and this codebase already has the exact technique for the second piece:
`ago-landing/styles.css`'s own `.hero::before`:

```css
background: radial-gradient(620px 260px at 22% 40%, var(--blue-glow), transparent 70%);
```

A widget-header equivalent, expressed as a layered `background` (radial accent composited over a
darkened flat base, both read from the one CSS variable this pipeline already has):

```css
.ago-header {
  background:
    radial-gradient(140% 140% at 100% 0%, color-mix(in srgb, var(--ago-accent) 55%, white 15%), transparent 60%),
    color-mix(in srgb, var(--ago-accent) 82%, black);
}
```

(Values illustrative, not final - meant to be tuned against the real render, not copied verbatim.)

**This reframes, rather than closes, the open question below.** The reference's own corner blob reads as
a genuinely separate hue from its base (bright green over dark navy-slate) - which either means a real
competitor brand accent independent of any "primary color" concept, or a large deliberate
lighten/desaturate shift on one derived value. Both of the options below still apply; what changes is
that "derive it algorithmically" now has a concrete shape to derive *into* (a radial highlight, not a
linear two-stop blend), which reads closer to "looks like the reference" than a plain linear gradient
would.

## The one real open question

**How is the gradient's second stop (or, per the reference model above, the radial accent's own color)
derived from a tenant's single configured color?** Two honest options, named rather than picked
silently:

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

Recommendation, not a decision: the derived (single-input) approach, shaped like the reference model
above (a radial highlight over a darkened flat base, both pure functions of `--ago-accent`) - it matches
"dominant primary color" literally, ships with no wire/console change, and is reversible into the
second option later if a tenant ever wants to pick both independently.

## Scope

- Once the derivation approach is confirmed: change `.ago-header`, `.ago-message--operator .ago-bubble-content`,
  `.ago-contact-capture-submit`/`.ago-primitive-form-submit`, `.ago-launcher`, and any other
  `background: var(--ago-accent)` site in `styles.ts` that reads as a primary surface (not every
  `--ago-accent` use is a fill - some are outlines/text color and should very likely stay flat) to the
  chosen gradient model built from `--ago-accent` alone.
- Keep every derived value computed in CSS (`color-mix`/`radial-gradient` expressions referencing
  `--ago-accent` directly), not duplicated as a second custom property `ui/widget.ts` would need to set -
  one source of truth for the tenant's color, the gradient is a pure function of it.
- Tune the reference model's own illustrative numbers (blob size/position, `color-mix` percentages)
  against a real render before calling it done - they are a starting point, not a spec.

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
