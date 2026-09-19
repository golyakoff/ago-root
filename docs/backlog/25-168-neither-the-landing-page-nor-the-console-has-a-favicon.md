# 25-168 · Neither the landing page nor the console ("офис") has a favicon

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-19, the author asked for a favicon carrying the same gradient "A" mark as the
  brand logo, for `ago-landing` - then clarified both surfaces need one: the console ("офис") as well.

## What is actually true today

Checked both repositories directly - neither serves a favicon, and neither `<head>` even references
one (so this is not a broken link to a missing file; the tag itself has never existed):

- `ago-landing/index.html` - no `<link rel="icon">` of any kind, no favicon file anywhere in the
  repository.
- `ago-console/index.html` - same: no icon `<link>`, no favicon file.

`ago-landing` already has the gradient mark the author is asking to reuse - `ago-landing/styles.css`'s
own `.brand .g`:

```css
.brand .g{width:28px;height:28px;border-radius:8px;background:linear-gradient(140deg,var(--blue),var(--violet));
  display:grid;place-items:center;color:#fff;font-size:14px;}
```

a gradient square with a white "A" inside, `linear-gradient(140deg,var(--blue),var(--violet))` -
`var(--blue)`/`var(--violet)` are `ago-landing/styles.css`'s own top-level custom properties. The
console's own brand mark (`ago-shell__glyph`, `25-167`) is a **flat** `background: var(--ago-brand)`
square today, not a gradient - a real, separate visual difference between the two surfaces' brand marks
that this item does not resolve (see Out of scope).

## Scope

- Produce one favicon asset (an actual raster/ICO/SVG file, not just markup) carrying a gradient "A"
  mark visually consistent with `ago-landing`'s own `.brand .g` treatment (the gradient direction/colors
  above), sized/exported the way a favicon needs (a multi-resolution `.ico`, or a modern `<link
  rel="icon" type="image/svg+xml">` plus a raster fallback - implementer's call on which browsers this
  needs to support).
- Wire it into **both** `ago-landing/index.html` and `ago-console/index.html`'s `<head>`.
- The two surfaces do not have to use byte-identical files - `ago-console`'s own square is flat-colored
  today (`25-167`), not gradient, so a literal reuse of `ago-landing`'s asset would introduce a gradient
  the console's own header mark does not otherwise have. Decide once, explicitly, whether the favicon
  should still be gradient on both surfaces (a deliberate small divergence between "the favicon" and
  "the header mark") or whether the console's favicon should be flat to match its own header - the
  author's own request ("градиент... как в логотипе") points at the gradient version; recorded here
  since it is a real, visible choice, not because it is expected to be controversial.

## Out of scope

- Changing the console's own header brand mark (`.ago-shell__glyph`) to a gradient - not asked for here;
  `25-167` is only about that glyph's own size, not its fill. If the author wants the console's header
  mark itself to become a gradient to match, that is a new, separate finding.
- Any other landing-page or console branding work.

## Done when

- [ ] `ago-landing` serves a favicon with the gradient "A" mark, visible in a browser tab
- [ ] `ago-console` ("офис") serves a favicon, visible in a browser tab - gradient-or-flat decided
      explicitly per the Scope note above, not left to whichever the implementer defaults to
- [ ] Both `<head>`s reference the asset(s) correctly (confirmed by loading each app, not only by
      reading the markup)
