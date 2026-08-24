# Console design foundation: tokens, a closed component set, and an application shell

- **Stage**: 11 (added 2026-08-24, when the stage was widened to cover both surfaces — see
  `roadmap.md`'s own note on why the console pass is sequenced here rather than in its own stage)
- **Status**: done (2026-08-25)
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

- [x] An ADR records the tokens-plus-hand-rolled versus component-library decision, with the
      alternative it rejected and why.
- [x] Tokens exist as a single source, traceably derived from `ago-landing`'s palette and type.
- [x] All eleven components exist, and nothing beyond them was added.
- [x] The shell renders on every route, with permission-gated navigation and an active state.
- [x] All existing screens are retrofitted — **seven, not six**: `11-02` merged first, so this item
      adopted its `WidgetConfigPage` per the "whichever lands second adopts the other's result" note
      above. No behavioural change, and the existing Vitest suite (18 tests, 4 files) green without
      modification.
- [x] `color-scheme: light dark` is gone and no dark-theme claim remains anywhere.
- [x] Focus is visible everywhere, contrast passes at the sizes used, and the pre-existing
      `role="alert"` / `aria-label` semantics survive.
- [x] Exercised live against the local cluster.

## Outcome

`adr/0030` records the decision: design tokens in plain CSS custom properties plus a hand-rolled set
closed at eleven, no component library. The alternative it takes most seriously — and names as the one
most likely to become correct later — is a headless library (Radix / React Aria); it lost because the
two components where a headless library earns its keep, the modal and the select, are exactly the two
the browser now implements natively (`<dialog>`'s `showModal()`, `<select>`), and this console has one
select with two options and no modals. Measured cost of the result: 17.15 kB CSS, 3.74 kB gzipped.

Shipped in `ago-console`: `src/design/tokens.css` (the single token source, with every value traced to
an `ago-landing` colour or to a stated derivation rule, and every measured WCAG ratio recorded inline),
`src/design/base.css`, eleven components under `src/components/`, and the shell under `src/shell/`
(`AppShell` prop-driven and context-free so `/signup`, `/callback` and `/onboarding` — which mount
outside `PermissionsProvider` — can render it, plus `OperatorShell` for the gated routes).

Two colours from the landing could not survive at console sizes and were demoted rather than quietly
used: `#8f8ac9` (3.16:1 on white) is now borders and dots only, with `#565096` (7.04:1) carrying text,
and the landing's `--line` (1.24:1) is a separator only, with `--ago-line-strong` (3.62:1) as the edge
of every control so 1.4.11's 3:1 holds.

Two of the eleven ship without a consumer, deliberately: `Dialog` and `Textarea`. Using either on an
existing screen would have been a behaviour change — a confirmation step in front of the attachment
delete, and Enter no longer submitting the composer — which this presentation-only item excludes.
`11-06` owns the composer; `11-06`/`13-04` are the screens that will want the dialog.

Verified live against the local stack (`Ago.Chat.Api` on 5009, compose infra, console dev server on
5173), signed in as the real `demo-operator`: the queue rendering ~50 real assigned rows and the
waiting list, a real conversation's thread (`aria-label="Message thread"` intact), and — the useful
negative — the shell's navigation showing only **Queue** for an operator without `site:configure`,
with `/admin` and `/settings/widget` typed in directly still rendering their refusal branches with
`role="alert"` preserved. Focus was measured on a real keyboard `Tab` driven over CDP in headless
Chrome: `2px solid #4b3aff` at 2px offset, and the skip link genuinely slides into view.

One gap, stated rather than papered over: the *populated* states of the two `site:configure` screens
(the admin conversation table, the widget-config form) were exercised only through their code paths
and the build, not observed live, because that needs a second interactive login. Their empty and
refusal states were observed live. Worth five minutes at the next opportunity.

## Open questions

None. The one decision with real trade-offs (component library or not) is this item's own ADR to make
and defend; the two the author has already answered — light-only, and how far the landing brand
carries — are recorded above rather than left to be rediscovered.
