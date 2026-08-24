# Console design foundation: tokens, a closed component set, and an application shell

- **Stage**: 11 (added 2026-08-24, when the stage was widened to cover both surfaces — see
  `roadmap.md`'s own note on why the console pass is sequenced here rather than in its own stage)
- **Status**: ready
- **Depends on**: nothing new architecturally — `adr/0023` already chose React, `5-06` already
  scaffolded the app, and every screen this item restyles already exists. It does not depend on
  `11-02` shipping first; whichever lands second adopts the other's result, and `11-02` is the smaller
  retrofit of the two.

## Goal

The console looks like a product someone built on purpose. Today `ago-console/src/index.css` is
seventeen lines — a font stack, `margin: 0`, a `max-width` — under a header comment that defers the
design-system choice to `5-07`. `5-07` shipped the UI that deferral was waiting for and never made
the pass, and `10-03`, `11-02`, `12-03` and `13-04` have each since written "reuse whatever form/
button styling `5-07` already established". After this item there is something real to reuse: a token
set, a small closed component library, and an application shell every screen sits inside.

## Context to read first

`ago-console/src/index.css` — the seventeen lines, and the comment that explains how they got there.
`ago-console/src/pages/*.tsx` — all six screens; note what is already right and must survive the
retrofit (`role="alert"` on error text, `aria-label="Message thread"`, permission-gated rendering via
`usePermissions()` with its own comment about client-side hiding never being the real gate).
`ago-landing/index.html` — the project's existing visual identity, and this item's source of truth for
colour and type: Manrope for text, Unbounded for display, JetBrains Mono for code, a warm off-white
base (`#fdfcfa`, `#fbfaf7`, `#f1efe9`, `#e5e2da`), dark ink (`#0c1a19`, `#14141f`), a lavender accent
(`#d9d6ff`, `#8f8ac9`, `#ecebff`) and a mint tint (`#eafffb`). `adr/0023` — why React, and its note
about the owner-operations surface being part of why. `docs/adr/0029` — the widget's own fixed-fields
config, which is a tenant-facing decision and deliberately unrelated to how the console itself looks.
`CLAUDE.md`'s rule on dependencies: nothing gets added without saying what it replaces and why
hand-rolling is worse — that applies to npm exactly as it does to NuGet, and it is the whole substance
of this item's ADR.

## Scope

- **An ADR naming the approach**: design tokens plus a hand-rolled component set, or a component
  library (Radix, MUI, shadcn-style copy-in, or another). A real decision with real trade-offs —
  bundle size, control over appearance, upgrade cost, and how much of it a reviewer would consider
  justified for six screens. Decide it, argue it, record it.
- **Tokens taken from `ago-landing`, not invented**: colour, spacing scale, type scale, radii,
  elevation, focus ring. Adapted rather than copied wholesale — the landing page sells and can afford
  display type and large accents; the console is a tool someone sits in for hours, so density, type
  sizes and accent restraint are recomputed for a working screen. Manrope carries the interface,
  Unbounded is confined to the shell's identity, the palette comes across whole (author's decision,
  2026-08-24).
- **The component set, deliberately closed at eleven**: Button, Input, Textarea, Select, Field
  (label + description + error), Table, Badge, Panel, Alert, Spinner/Skeleton, Dialog. Anything not on
  that list is not in this item — the list is the scope boundary, not a starting point.
- **An application shell**: a persistent header carrying product identity, the current site, the
  signed-in operator and sign-out; navigation between the queue, the admin view and the widget-config
  screen, with an active state, permission-gated through the existing `usePermissions()` hook rather
  than a new mechanism. Today sign-out is a `<button>` inside a `<p>` and the admin link is a bare
  `<p><Link>`.
- **Loading, empty and error as first-class states**, replacing the ad-hoc `Loading…`, `Nothing
  waiting.` and bare `<p role="alert">` scattered through the pages. Keep the `role="alert"` semantics.
- **Retrofit all six existing screens** onto the shell and the components: `QueuePage`,
  `ConversationPage`, `AdminConversationsPage`, `OnboardingPage`, `SignupPage`, `CallbackPage`. This is
  a presentation change — no behaviour, no API calls, no realtime handling changes, so the existing
  Vitest suite stays green untouched rather than being rewritten around the new markup.
- **Drop the dark theme claim.** `index.css` declares `color-scheme: light dark`, which makes the
  browser paint form controls dark while nothing else responds — a half-claim that reads as a bug. The
  declaration goes; the console is light-only, deliberately and in writing (author's decision,
  2026-08-24). Anyone reinstating it owns doing both themes properly, including contrast checks.
- **An accessibility floor**: visible focus on every interactive element, text and interactive contrast
  that passes at the sizes actually used, every control labelled, and the existing `role="alert"` /
  `aria-label` usages preserved rather than lost in the rewrite.
- **Verified live**, not asserted from a screenshot of a dev server: the retrofitted console is used
  against the local cluster, and checked on the public deployment once it ships there — `CLAUDE.md`'s
  standing rule that UI changes are exercised live.

## Out of scope

- The operator workspace's own layout and interaction — `11-06`. This item restyles the screens that
  exist; that item changes what the operator's screen *is*. Split deliberately: a retrofit that keeps
  behaviour identical is reviewable in a way that a simultaneous redesign is not.
- The widget's appearance — `11-01`/`11-02`/`11-03` and `11-04`'s open branding question. The widget
  renders inside a stranger's page in a shadow tree and shares no styling with the console.
- `ago-landing` itself. It is the source of the tokens, and it is not modified here.
- Interface i18n — `vision.md` still lists it as out of scope.
- Any new screen. Screens arrive with `11-02`, `12-03` and `13-04`; this item gives them something to
  be built out of.

## Done when

- [ ] An ADR records the tokens-plus-hand-rolled versus component-library decision, with the
      alternative it rejected and why.
- [ ] Tokens exist as a single source, traceably derived from `ago-landing`'s palette and type.
- [ ] All eleven components exist, and nothing beyond them was added.
- [ ] The shell renders on every route, with permission-gated navigation and an active state.
- [ ] All six existing screens are retrofitted, with no behavioural change and the existing Vitest
      suite green without modification.
- [ ] `color-scheme: light dark` is gone and no dark-theme claim remains anywhere.
- [ ] Focus is visible everywhere, contrast passes at the sizes used, and the pre-existing
      `role="alert"` / `aria-label` semantics survive.
- [ ] Exercised live against the local cluster.

## Open questions

None. The one decision with real trade-offs (component library or not) is this item's own ADR to make
and defend; the two the author has already answered — light-only, and how far the landing brand
carries — are recorded above rather than left to be rediscovered.
