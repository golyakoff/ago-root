# 25-184 · The brandbook has no real theme toggle, and one page's "light-only" claim is stale

- **Stage**: 25
- **Status**: ready
- **Depends on**: `25-183` (the components/typography pages this item's own fix touches)
- **Found**: 2026-09-20, the author, asking directly whether the brandbook's dark/light handling is
  "just a dark background slapped on" rather than a real, properly split theme - checked against the
  real files rather than answered from impression.

## What is actually true today

`ago-brandbook/styles.css` defines its whole palette as CSS custom properties, split correctly at the
token level (`--bg`/`--panel`/`--ink`/... each have a real light value and a real dark value, not one
color with an alpha overlay) - so the underlying practice this item asks for is *already* followed for
the page's own chrome. But:

1. **There is no manual toggle at all** - only `@media (prefers-color-scheme: light)`. The bare
   `:root` block is the dark palette with no `[data-theme]` override anywhere in the file, and there
   is no JS in the repository (`find ago-brandbook -name '*.js'` returns only `tokens.js`, the color/
   type data array - no toggle logic). A visitor's OS setting is the only thing that decides, and nothing
   lets them override it - unlike `ago-landing`, which already ships exactly this as a real, working
   feature: `data-theme="light"|"dark"` on `<html>`, written by a toggle button, persisted to
   `localStorage`, with "no attribute" meaning "follow the OS" (`ago-landing/i18n.js`'s own
   `agoSetTheme`/`agoPaintThemeToggle`, `styles.css`'s dark-first `:root`/`:root[data-theme="light"]`/
   `@media (prefers-color-scheme: light){ :root:not([data-theme="dark"]) }` cascade). `ago-console`
   ships the identical three-state pattern again (`src/design/theme.ts`, `tokens.css`'s own header
   comment). The brandbook is the one static page in this family that never got it.

2. **`components.html`'s own header comment (`25-183`) asserts something no longer true.** It says:
   "Every selector below that starts with `.ago-` is copied verbatim from `components.css` (light
   theme only - the console ships light-only, tokens.css's own header comment cites `adr/0030`'s
   2026-08-26 amendment for why)." **That is stale**: `tokens.css`'s own header goes on, in the same
   comment block, to say the *opposite* - `adr/0030` point 4's original light-only decision was
   **reversed**, same date, same author's addendum: "This addendum is the opposite shape: every
   colour token below gets a real, measured dark value... Activation is three-state - system / light /
   dark." The console has shipped a real, contrast-checked dark theme since that reversal. The
   `components.html` comment (and the demo's actual markup, which only ever renders the light values)
   describes a state that was already false on the day it was written - `25-183`'s own review checked
   the font-loading claim against both real `index.html` files, but did not check this dark-theme claim
   against the same file it was quoting.

## Goal

Two parts, one promise ("the brandbook's own theme handling is real, not decorative"):

1. **A real toggle**, mirroring `ago-landing`'s own mechanism exactly rather than inventing a second
   one: `data-theme` attribute on `<html>`, a toggle button in the shared page nav (every page already
   has one, from `25-183`'s own multi-page nav bar), `localStorage` persistence, "no attribute" meaning
   "follow the OS". `styles.css`'s existing `:root`/`@media (prefers-color-scheme: light)` split
   becomes the dark-first three-state cascade `ago-landing`/`ago-console` already both use (bare
   `:root` = dark, `:root[data-theme="light"]` = light, `@media (prefers-color-scheme: light){
   :root:not([data-theme="dark"]) }` = light-when-the-OS-says-so-and-nothing-overrides). This is a
   token-level change to values already split correctly - not a new palette.
2. **Fix `components.html`'s stale claim**, and decide what the demo should actually show now that
   the premise (console is light-only) is false. This is a real, small design decision, not a
   mechanical text fix - two honest options, not a foregone one:
   - Show the console's real dark tokens too (a second `.console-demo` variant, or the demo simply
     following the brandbook's own toggle using the console's *actual* dark values copied in the same
     hand-authored way `components.css` already copies the light ones) - the more complete answer, and
     the one that actually demonstrates what "the console has a real dark theme" means.
   - Or, keep the demo light-only **on purpose** and say so honestly instead of citing a reversed
     decision as if it still held - a defensible choice (a components reference showing one theme
     fully beats two themes shown thinly) but only if the page says *why* instead of citing a stale
     reason.
   Either is acceptable; citing the reversed `adr/0030` point 4 as current is not.

## Out of scope

- Any change to `ago-console`'s or `ago-landing`'s own theme mechanisms - both are correct and
  already shipped; this item only brings the brandbook's own chrome up to the same standard and fixes
  what it says about the console's.
- Redesigning the palette itself - the light/dark values in `styles.css` already exist and are
  already correctly split; this item wires a toggle to values that are already right, and (for the
  components page) either sources or explicitly declines the console's own equivalent values.

## Done when

- [ ] `ago-brandbook` has a working toggle button, present via the shared page nav on every page,
      switching `data-theme` on `<html>`, persisted in `localStorage`, defaulting to
      `prefers-color-scheme` when nothing is stored - functionally identical to `ago-landing`'s own
      mechanism, confirmed live in a browser (toggle, reload, confirm the choice survives).
- [ ] Every token in `styles.css` resolves correctly in all three states (system-light, system-dark,
      explicit override in each direction) - checked by toggling live, not by reading the CSS and
      assuming it composes.
- [ ] `components.html`'s header comment no longer cites the reversed `adr/0030` point 4 as the reason
      the demo is light-only, and the page's actual behaviour (light-only-on-purpose-with-a-real-reason,
      or a real dark variant sourced from `tokens.css`'s own dark block) matches whatever the comment
      now says.
- [ ] `docker build` still succeeds and the built image serves every page correctly in both themes -
      checked by running it locally.
- [ ] Deployed and confirmed live the same way `25-180`/`25-183` were.
