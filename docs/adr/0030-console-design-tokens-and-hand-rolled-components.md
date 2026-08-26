# ADR-0030: Design tokens and a closed hand-rolled component set for the console, not a component library

- **Status**: Accepted, and **amended on 2026-08-26** — a second surface now reads these tokens (the
  Keycloak login theme, `11-07`), and it answers the webfont question in the last "Negative"
  consequence below *differently* from the console. That bullet still describes the console
  correctly; it no longer describes the whole product. The amendment immediately following says what
  changed and why the same trade-off came out the other way one screen earlier.
- **Date**: 2026-08-25 (amended 2026-08-26)
- **Stage**: 11

## Amendment (2026-08-26): the login page loads no webfont, and the tokens now have a second consumer

`11-07` put an AGO theme on Keycloak's login, registration, password-reset, email-verification, info
and error pages — the screens that sit between the landing page and the console, and that until then
were whatever the upstream image shipped. Two things in this ADR need updating as a result.

**1. The webfont trade-off was re-examined for a different context, and reversed there.** The
"Negative" list below says fonts come from Google Fonts, and weighs that for a dashboard an operator
opens after signing in. The login page is not that: it is the one page in the product where a
third-party request sits next to a password field, and it is the first screen of the first visit, so
its font is the one most likely to be fetched cold rather than served from cache.

**The login theme therefore loads no webfont at all.** It uses the system tail of the console's own
stack — `--ago-font-sans` with `"Manrope"` dropped — under its own name, `--ago-login-font`. The
identity survives on colour, spacing, radii and elevation, which is the larger part of what these
tokens are; a reviewer sees the same palette and the same geometry, set in the platform's UI face.

This is deliberately *not* extended to the console, and the reason is not consistency-for-its-own-sake
in reverse. The console's whole visual argument rests on matching a landing page we do not get to
change, it is a shift-long tool where the fetch happens once, and `11-05` already spent real effort
on Unbounded as the shell's identity. A login page has one line of chrome and no wordmark to set.

Measured rather than argued: driven through headless Chrome over CDP against a local Keycloak, the
sign-in page issues **eleven requests, all same-origin** — Keycloak's own PatternFly stylesheets, the
theme's two stylesheets, three of its scripts, and one FontAwesome `.woff2` that the upstream image
serves itself. There is no third-party origin in the list, so there is no font host that can be slow,
blocked or watching. That also makes the degraded state trivial in a way the console's is not: there
is nothing to fail.

Self-hosting Manrope inside the theme stays the upgrade path if the type turns out to matter. It is a
bigger change than it sounds — the theme is delivered as a ConfigMap precisely because it is two text
files, and font binaries are the thing that ends that.

**2. Point 1 of the Decision — "one token source" — now spans two repositories.** The theme cannot
`@import` `tokens.css`: it is mounted into a container that has no `ago-console` anywhere near it, so
the values have to physically be in the stylesheet. That is a vendored copy, and a vendored copy of a
colour is exactly the failure this project has had before.

The copy is therefore **generated and checked, never typed**: `ago-deploy/k8s/check-theme-tokens.sh`
reads `ago-console/src/design/tokens.css`, collects the tokens the theme's own stylesheet actually
references, rebuilds the block between `GEN-BEGIN`/`GEN-END` markers, and exits non-zero on any
difference. `redeploy.sh` runs it after pulling both checkouts. The one deliberate divergence — the
font stack — is checked too, as a suffix relation rather than an equality.

The rule in point 1 is thus unchanged in substance and wider in reach: `tokens.css` is still the
single source; a literal colour in the login theme is still a defect; and there is now a script that
says so rather than a convention that hopes so. `ago-deploy` has no CI to hang that check on
(`adr/0015`'s pipelines are the two backend repositories only), so outside a redeploy it runs when a
person runs it — stated here rather than implied.

## Context

`ago-console` reached seven screens — the queue, a conversation, the site-wide admin list, onboarding,
signup, the OIDC callback, and `11-02`'s widget-appearance form — on seventeen lines of CSS. Those
seventeen lines were a font stack, `margin: 0`, a `max-width` and a `color-scheme: light dark`, under a
comment deferring the design-system choice to `5-07`. `5-07` shipped the UI the deferral was waiting
for and never made the pass, and `10-03`, `11-02`, `12-03` and `13-04` each wrote "reuse whatever
form/button styling `5-07` already established" into their own scope. There is nothing to reuse. That
is what `11-05` is for, and the choice of *what* to build has to be made before anything is built.

The forces are not the usual ones, and saying so plainly matters more than surveying the market:

- **The surface is small and closed-ish.** Seven screens now, three more planned (`11-06`, `12-03`,
  `13-04`). The item fixes the component set at eleven — Button, Input, Textarea, Select, Field,
  Table, Badge, Panel, Alert, Spinner/Skeleton, Dialog — and treats that list as a scope boundary
  rather than a starting point. A library is priced for a surface that grows; this one is bounded by
  decision, not by luck.
- **A visual identity already exists and is not negotiable.** `ago-landing` is live, and `11-05`'s
  author fixed the palette as carrying across whole. Whatever is adopted has to wear Manrope,
  Unbounded, JetBrains Mono, a warm off-white paper family and a lavender/indigo accent — none of
  which is any library's default.
- **`CLAUDE.md`'s dependency rule applies to npm exactly as to NuGet**: nothing is added without
  saying what it replaces and why hand-rolling it is worse. That rule is the whole substance of this
  decision, and it cuts both ways — it is equally an argument against hand-rolling something a
  library does *better*.
- **This is a portfolio project judged on whether a senior reviewer calls the code correct and
  well-reasoned.** Both "pulled in MUI" and "hand-rolled a modal badly" are answers a reviewer would
  mark down. The interesting question is which parts are genuinely hard.
- **The console is an internal tool an operator sits in for a shift**, not a page a visitor skims.
  Density and legibility matter more than delight; there is no marketing surface to serve.

The honest difficulty is not buttons and panels. It is the accessibility contract on the few
components where the platform historically gave you nothing: focus trapping and restoration in a
modal, `aria-describedby` wiring on fields, live-region roles on messages, and combobox keyboard
behaviour. Any decision that waves at those has not engaged with the real cost.

## Decision

**Design tokens in plain CSS custom properties, plus a hand-rolled component set closed at eleven. No
component library, no CSS framework, no CSS-in-JS runtime.** Concretely:

1. **One token source**, `src/design/tokens.css`. Every colour, space, type size, radius, shadow and
   focus value in the application is a custom property declared there. Each is either carried over
   from `ago-landing/index.html` unchanged (the whole palette, the three type families) or derived
   from a landing value by a rule written next to it (spacing becomes a 4px ramp, the landing's 28px
   and 18px radii halve, its shadow distances halve, its 16px body drops to 15px). A literal colour
   or size anywhere else in `src/` is a defect. The point is traceability: a reviewer can open the
   landing page and check the arithmetic.
2. **Eleven components**, each a thin wrapper over the correct native element that spreads the rest of
   its props through, so `disabled`, `type`, `onClick` and every `aria-*` keep working as the DOM
   defines them. This is what let seven existing screens be restyled with no behavioural change and
   the existing Vitest suite green without modification.
3. **The platform does the hard parts.** `Dialog` is the native `<dialog>` element driven by
   `showModal()`, which is what makes this decision defensible rather than hand-wavy: focus trapping,
   focus restoration, inertness of the rest of the page, Escape handling and the backdrop are the
   browser's, not ours. `Select` is a styled native `<select>`; its option list stays the platform's
   popup. We hand-rolled the styling, not the accessibility semantics.
4. **Light only.** `color-scheme: light dark` is removed. It made the browser paint native form
   controls dark while nothing else responded — a half-claim that read as a rendering bug. Reinstating
   a dark theme means building both properly, contrast checks included.
5. **Contrast is measured, not eyeballed.** Every foreground/background pair the tokens are meant to
   produce has its measured WCAG ratio recorded inline in `tokens.css`. Where a landing colour could
   not clear the bar at console sizes it was demoted to decoration and a derived value that does clear
   it was declared beside it — `#8f8ac9` is 3.16:1 on white and is now borders-and-dots only, with
   `#565096` (7.04:1) carrying anything with a glyph in it. The landing's `--line` (1.24:1) is fine as
   a separator and is not allowed to be the edge of a control; `--ago-line-strong` (3.62:1) is,
   satisfying 1.4.11.

## Consequences

**Positive.**

- No new dependency, and therefore no new upgrade treadmill, no transitive supply chain, and no
  library major version that arrives on someone else's schedule. The whole design system is 17.15 kB
  of CSS (3.74 kB gzipped) in the production build, measured, not estimated.
- Complete control over an identity that had to match a page we do not get to change.
- Every accessibility decision is visible in this repository rather than inherited: the roles, the
  `aria-describedby` wiring and the focus rule are readable in about four hundred lines.
- One global `:focus-visible` rule means a control added later cannot ship without a visible ring,
  which is the failure mode a per-component approach actually has.

**Negative, and these are real.**

- **We now own the accessibility of eleven components forever.** The platform covers the modal and
  the select, but `Field`'s label/description/error wiring, `Alert`'s live-region roles and the
  keyboard behaviour of anything added later are ours to keep correct. A library has thousands of
  users finding those bugs; we have one.
- **There are no component tests.** The existing Vitest suite covers pure protocol logic and runs
  under `src/**/*.test.ts` with no DOM testing library installed. Adding one is a dependency decision
  in its own right and was out of `11-05`'s scope, so the components are currently verified by
  typecheck, lint, live use and manual keyboard/CDP checks — not by assertions. This is the weakest
  point of the decision and should be revisited when the set is next touched.
- **The eleventh component has no consumer yet.** `Dialog` and `Textarea` ship unused, because using
  either on an existing screen would have been a behaviour change (a confirmation step in front of a
  destructive action; Enter no longer submitting the composer). Unused code is a cost; the item's list
  is closed at eleven and names both, and `11-06`/`13-04` are the screens that need them.
- **The closed list will be tested.** The first screen that wants a tab bar, a combobox, a date picker
  or a toast will make this decision look like the wrong one for a moment. That is the point at which
  to re-open this ADR, not to quietly add a twelfth component.
- **Fonts come from Google Fonts** via the same `<link>` the landing page uses, rather than a
  self-hosted npm package. That keeps `package.json` unchanged but adds a third-party request on first
  paint and a privacy consideration once the console is public. Every stack falls back to a system
  font, so a blocked request degrades rather than breaks. Self-hosting is the obvious follow-up when
  the console gets a Content-Security-Policy. **This bullet is about the console only** — see the
  2026-08-26 amendment above: the login theme reached the opposite answer for the screen that carries
  a password field.

## Alternatives considered

**A headless library — Radix UI, React Aria, Headless UI.** The strongest alternative, and the one a
reviewer is most likely to ask about. It gives exactly the part that is genuinely hard (focus
management, ARIA wiring, keyboard interaction) and leaves styling entirely to us, so the `ago-landing`
identity would have been unaffected. Rejected because of what this console actually contains: one
`<select>` with two options and zero modals in seven screens. The components where a headless library
earns its keep are the ones we do not have, and the two that come closest — the dialog and the select
— are exactly the two the browser now implements natively. Buying a dependency to solve problems this
application does not have is the definition of premature. **This is the alternative most likely to
become correct later**: the first real combobox, menu, or tooltip is the trigger to revisit.

**A styled component library — MUI, Mantine, Chakra.** Rejected on identity and cost together. Each
ships an opinionated visual language, and the work would have been fighting it back to `ago-landing`'s
palette and type — theme overrides that are harder to read, and much harder to review, than the CSS
they replace. They are also large: MUI's core plus its emotion runtime is comfortably an order of
magnitude more shipped bytes than 3.74 kB gzipped, for seven screens. A reviewer would reasonably ask
what it bought.

**shadcn-style copy-in.** Genuinely appealing: no dependency in `package.json`, components live in the
repository, and they are Radix underneath. Rejected because copy-in is only a saving when you take the
whole idiom with it — Tailwind, `class-variance-authority`, `tailwind-merge`, and the generator. Taken
piecemeal it is Radix with extra steps, at which point the previous alternative's reasoning applies;
taken whole it is a utility-CSS framework decision made sideways rather than argued. It also owns the
same forever-maintenance cost as hand-rolling, since copied code does not update, without the benefit
of having been written for this palette.

**Tailwind CSS.** Rejected for this codebase specifically. It solves a problem — naming things, and
stylesheet growth over time — that eleven components and a closed list do not have, and it would put
the token values into a config file and the composition into `className` strings, which is strictly
less legible for a reviewer than named custom properties and a single stylesheet. Tailwind's real
strength is a large team shipping many screens; this is one author shipping ten.

**CSS Modules or CSS-in-JS.** Rejected as scope-mismatched. Scoping solves collisions across a large
stylesheet with many authors; a closed eleven-component set with an `ago-` prefix has no collision
problem to solve. CSS-in-JS additionally adds a runtime and a rendering-path cost for styling that is
entirely static.

**Do nothing, keep the seventeen lines.** The status quo, and worth naming because it had lasted four
backlog items. Rejected because four separate items had already deferred to a design pass that did not
exist, the deferral was compounding, and `color-scheme: light dark` was actively rendering a bug.
