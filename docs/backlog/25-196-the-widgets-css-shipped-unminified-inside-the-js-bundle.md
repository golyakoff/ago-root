# 25-196 · The widget's CSS shipped unminified inside the JS bundle

- **Stage**: 25
- **Status**: done — `ago-widget#115`
- **Found**: 2026-09-21, the author, reviewing why a single verbose CSS comment (added during
  `25-193`'s own review) pushed the gzipped bundle from ~46.0 KB over the 46 KB budget test. The
  author's own question: doesn't `minify: true` strip comments? It does - for JavaScript.

## What was actually true

`ui/styles.ts` held the widget's entire CSS as a JavaScript template literal string. `build.mjs`'s
own `minify: true` (esbuild, four separate build calls) is a *JavaScript* minifier - it strips real
JS comments and collapses JS whitespace, but the characters between a template literal's backticks
are a string *value* to it, not code. A minifier cannot touch bytes inside a string literal without
changing the program's actual output, so every CSS comment and all of `ui/styles.ts`'s own
indentation shipped to production verbatim, inside the JS bundle, for no functional reason -
CSS-shaped content the build's own minification pass was structurally unable to see as CSS at all.

## Fix

Moved the CSS out of the template literal into a real `src/ui/styles.css` - genuine CSS syntax, no
`/* css */` tag trick needed. `build.mjs` reads it and runs esbuild's own CSS-aware `transform`
(`loader: "css", minify: true`) once at build time, producing real minified CSS text (comments
gone, whitespace collapsed, safe rule merging where applicable). That text is inlined into
`dist/widget.js` via `__AGO_WIDGET_CSS__`, the identical `define` mechanism `__AGO_WIDGET_VERSION__`/
`__AGO_COMMIT__` already use - `ui/shadow-root.ts` declares and reads it exactly as `index.ts`
already does for those. `vitest.config.ts` defines the same identifier from the same source file,
unminified, for tests.

Every doc comment across the codebase pointing at `ui/styles.ts` as "where this CSS rule lives"
was updated to `ui/styles.css` in the same change - a name, not a rewrite of the reasoning each
comment carries.

## Measured

**37.7 KB gzipped** (145.7 KB raw), down from a freshly-measured **46.0 KB** on the immediately
preceding commit - **-8.3 KB gzipped**, real headroom back under the 46 KB budget rather than a
one-comment-at-a-time trim. `README.md`'s own "Bundle size" log has the full entry.

## Done when

- [x] The widget's own injected CSS ships with comments stripped and whitespace collapsed in the
      real built `dist/widget.js` - proven by a new test that runs a real build and asserts a known
      source comment is present in `styles.css` but absent from the bundle, while a real rule from
      beside it survives. Fails-before/passes-after confirmed directly (temporarily reverted the
      transform call, watched the comment reappear, restored it).
- [x] `ux-gate`'s own WCAG-contrast test (reads real computed styles inside the shadow root against
      the built artifact) still passes - the closest thing this repository has to a live check that
      the minified CSS still renders identically.
- [x] `npm run typecheck`/`lint`/`test`(484/484)/`ux-gate`(16/16) all green.
- [x] `README.md`'s "Bundle size" section carries the real measured before/after.
