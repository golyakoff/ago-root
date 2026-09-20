# 25-172 · The channel-switcher card's icons are placeholder glyphs, not the real brands

- **Stage**: 25
- **Status**: done — `ago-widget#106` (`3bb24bc`). Independently re-verified by the managing session
  before merging: diff reviewed line-by-line against the approved icon sources, and all four commands
  (`typecheck`/`lint`/`test`/`ux-gate`) re-run directly rather than trusting the worker's own report —
  462/462 unit tests, 16/16 `ux-gate`.
- **Depends on**: nothing (`25-149` already shipped the card this item changes)
- **Found**: 2026-09-20, the author asked why golyakov.net showed no Telegram/MAX buttons; that
  investigation surfaced `25-149`'s own commit note admitting its three non-Telegram icons were
  "placeholder glyphs, not a verified reproduction of any provider's real trademarked mark." The author
  then prepared and approved real brand assets against a live HTML review artifact before this item
  was filed - see Scope for exactly what was approved and why.

## What is actually true today

`ago-widget/src/ui/widget.ts`'s channel-switcher card (`25-149`, the row above the composer) renders
each channel with `createSvgIcon(d)` - one `fill: currentColor` path in a shared `0 -960 960 960`
viewBox, colored by `CHANNEL_BRAND_COLORS[link.kind]` set on the row's own `style.color` (which also
tints the row's label text, since `.ago-channel-switcher-row { color: inherit }`). `CHANNEL_ICON_PATHS`'s
own comment says plainly that only Telegram's path is a real icon (it reuses the composer's own verified
"send" glyph, which happens to double as Telegram's logo concept); MAX/VK/WhatsApp are invented
placeholder shapes with invented placeholder colors.

## Scope

Approved final assets (reviewed and confirmed live by the author against an HTML mockup, not merely
described): **Telegram**, **WhatsApp**, **VK**, **MAX** - four real, multi-color/multi-path brand icons,
sourced by the author and finished this session:

- **Telegram** — the provider's own icon, recolored to the official `#0088CC` (the source asset carried
  an incorrect `#40B3E0`).
- **WhatsApp** — the provider's own icon (a circular badge with a phone-handset cutout), recolored to
  `#2AB540`. The cutout was originally an unfilled `evenodd` hole (relying on whatever page background
  showed through it - invisible on a dark ground); fixed by adding an opaque white layer under the
  cutout so the handset renders white regardless of background.
- **VK** — composited from two of the author's source files: the circular outline from one, recolored to
  `#345E90` (the VK mark itself rendered in white as a second, explicit path - not an `evenodd` cutout,
  learning directly from the WhatsApp fix above).
- **MAX** — the provider's own gradient icon, used as-is but **cropped to a true circle** (its native art
  is a rounded square, `rect ry="249.681"` on a `1000x1000` viewBox) so it matches every other channel's
  circular badge - confirmed live against the approved review, the alternative (keep it a rounded square)
  was explicitly rejected.

Full source content for all four is in this item's own implementation notes (or re-derive from
`C:\git\ago\images\{telegram,whatsapp,vk,max}.svg` if that path still holds when this is picked up -
confirm it exists before assuming so, per this repository's own "verify before ready" convention).

**Avito is deliberately not part of this item.** `25-147`'s own scope means `ChannelLinkResponse.Kind`
can never actually carry `Avito` today (no `PublicHandle` support exists for it) - `CHANNEL_ICON_PATHS`
already only lists the four kinds that can appear, and this item does not add a fifth entry nothing can
ever look up. An Avito icon file was prepared and approved alongside the other four for exactly this
reason - reuse it without re-deriving it once Avito gets a `PublicHandle` path (a separate, unfiled
future item), rather than sourcing a sixth icon from scratch at that point.

### The rendering-mechanism change this requires

`createSvgIcon`'s single-path, `fill: currentColor` shape cannot render a multi-color, multi-path icon.
Do not touch `createSvgIcon` itself - it has other callers (`sendButton` and every other composer
control) and stays exactly as it is, including as the *fallback* path for an unrecognised future
`ChannelKind` (`CHANNEL_FALLBACK_ICON_PATH`/`CHANNEL_FALLBACK_COLOR`, unchanged).

For the four recognised channel kinds only, add a second, parallel mechanism that builds a real SVG
subtree from structured data - **not `.innerHTML` with a markup string**: this codebase has no
`innerHTML` anywhere in `widget.ts` today, building every element via `createElementNS`/`setAttribute`
instead, and a raw-embedded-third-party-site widget is exactly the context where that discipline is
worth keeping (some hosting sites' own CSP may disallow it). A small recursive shape/builder covers every
one of the four icons cleanly, since MAX alone needs nested `<defs>`/`<linearGradient>`/`<radialGradient>`
in addition to `<rect>`/`<path>`:

```ts
interface IconNode {
  tag: string;
  attrs?: Record<string, string>;
  children?: IconNode[];
}
// a small recursive function walks this into real SVGElement nodes via createElementNS, mirroring
// createSvgIcon's own construction style exactly - attrs set via setAttribute, nothing via innerHTML.
```

**Decouple text-tint from icon color.** Today one `row.style.color` assignment colors both the label
text (via CSS `color: inherit`) and the icon (via the icon's own `fill: currentColor`). The four real
icons carry their own explicit fills and must never read `currentColor` - so `CHANNEL_BRAND_COLORS`
becomes text-tint-only going forward. Update its three real values to the same authoritative brand
colors this item lands in the icons themselves (`Telegram: "#0088CC"`, `WhatsApp: "#2AB540"`,
`Vk: "#345E90"`); leave `Max` as its existing placeholder purple (`#6E56CF`) - MAX's official mark is a
gradient with no single flat hex to promote to text-tint duty, and inventing one is out of scope here.

## Out of scope

- Avito's icon (see above - the asset exists, prepared, but nothing wires it in yet).
- Any change to `createSvgIcon` itself or to any of its other (composer-button) callers.
- The "bottom row" / launcher-adjacent circular buttons and the console top-vs-bottom placement setting
  - filed separately as `25-173`, not built here. This item only replaces the icons the existing,
    already-shipped card (`25-149`) uses.
- Re-deriving or re-approving the icon assets themselves - that already happened, live, before this item
  was filed; this item is the implementation, not a second design pass.

## Done when

- [x] Telegram, WhatsApp, VK and MAX each render their real, multi-color brand icon in the
      channel-switcher card. — `CHANNEL_ICON_TREES`/`buildIconTree` (`ui/widget.ts`), the exact approved
      source content transcribed verbatim; confirmed by dedicated tests asserting each of Telegram/
      WhatsApp/VK renders more than one `<path>` (`channelSwitcher.test.ts`) and independently re-checked
      against the diff by the managing session before merging.
- [x] MAX's icon renders as a true circle, not its native rounded-square shape. — `clip-path:circle(50%
      at 50% 50%)` in its icon tree's own `style` attribute, asserted by its own test.
- [x] The row's label text keeps its existing per-channel color tint, now independent of the icon's own
      (unrelated, multi-color) fill. — `CHANNEL_BRAND_COLORS` still drives `row.style.color`; a dedicated
      test confirms it still resolves to the brand hex while the icon's own `fill` is never `currentColor`.
- [x] `createSvgIcon` and every one of its other callers are byte-for-byte unchanged; the unrecognised-
      `ChannelKind` fallback row still renders `CHANNEL_FALLBACK_ICON_PATH` exactly as before. — confirmed
      directly in the diff: `createSvgIcon` itself has zero changed lines; `buildBrandIcon(kind) ??
      createSvgIcon(CHANNEL_FALLBACK_ICON_PATH)` is the only new call site.
- [x] No `.innerHTML` assignment anywhere in the new code - every new SVG node built via
      `createElementNS`/`setAttribute`, matching this file's own existing convention. — `buildIconTree`
      is a small recursive `createElementNS`/`setAttribute` walker; confirmed no `.innerHTML` in the diff.
- [x] `npm run typecheck`, `npm run lint`, `npm run test` and `npm run ux-gate` all green. — re-run
      independently by the managing session (not merely trusted from the worker's report): 0 typecheck
      errors, 0 lint errors, 462/462 unit tests, 16/16 `ux-gate`.
