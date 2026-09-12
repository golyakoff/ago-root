# 25-48 · An Appearance settings page picks the theme

- **Stage**: 25
- **Status**: ready — **not yet verified against the real code** (docs/backlog/README.md)
- **Depends on**: nothing to build against — `25-47`'s own user menu links here, but this page must
  exist on its own regardless of when that lands
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

`ago-console` has no theme picker today. The author wants one, referencing GitHub's own
`/settings/appearance` shape.

## Scope

- A new, standalone page (own route) offering exactly three choices: **System**, **Light**, **Dark**.
- The choice persists per operator (not per tenant, not per device only — check whether this console
  already has an operator-level preference-storage mechanism before inventing one; if none exists,
  `localStorage` is an acceptable starting point, named as a deliberate scope limit rather than
  silently assumed).
- "System" follows the OS/browser's own `prefers-color-scheme`; the console does not currently need a
  full dark theme built from scratch if one already exists — this item wires the picker, it does not
  invent the palette if the console has no dark styles yet (name that gap explicitly if found, rather
  than silently building one from scratch as a side effect).
- Nothing else lives on this page yet, per the feedback's own words.

## Where this is likely to go wrong

- **Check whether a dark theme/token set already exists in `ago-console` before assuming this item
  must build one.** If it doesn't, that's a real, separate finding — report it rather than quietly
  inventing a full dark palette as an undocumented side effect of "just wiring a picker."

## Done when

- [ ] `/settings/appearance` (or the console's own equivalent route convention) offers System/Light/Dark.
- [ ] The choice persists across a reload for the same operator.
- [ ] "System" actually follows the OS/browser preference, proven by a test or a manual check with
      `prefers-color-scheme` toggled.
