# ADR-0030: Design tokens and a closed hand-rolled component set for the console, not a component library

- **Status**: Accepted, and **amended five times** — on 2026-08-26 (a second surface now reads these
  tokens, the Keycloak login theme, `11-07`, and answers the webfont question in the last "Negative"
  consequence below *differently* from the console), on 2026-09-05 (`23-24` opens the closed
  eleven-component set by exactly one glyph, narrowly, for one meaning), on 2026-09-06 (`23-31`/
  `adr/0129` closes that opening again — the meaning the glyph existed for is gone, and nothing
  replaces it with a second one), on 2026-09-12 (`25-47` reopens it a third time, for three
  glyphs and the console's first real dropdown menu), and again on 2026-09-12 (`25-54` grows the set
  itself for the first time since `11-05` — a twelfth component, the tooltip this ADR's own
  Alternatives section named as its trigger to revisit). All five amendments are appended below the
  Decision they modify; none rewrites the original text.
- **Date**: 2026-08-25 (amended 2026-08-26, amended 2026-09-05, amended 2026-09-06, amended 2026-09-12,
  amended 2026-09-12)
- **Stage**: 11, second amendment `23`, third amendment `23`, fourth amendment `25`, fifth amendment `25`

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

## Amendment (2026-09-05): one glyph, narrowly, not a reopening of the closed set

`23-24` (`docs/design/decisions.md` §10) needed the navigation to mark an entry the signed-in
operator cannot use but a colleague at this tenant could grant them — muted text plus a small lock
mark beside the label, leading to a refusal page that says who can fix it. The Decision above closes
the component set at eleven *on purpose*, and `docs/design/gaps.md` pile 3 item 3 records "no icon
set, and no icon-only button" as one of the ten real open questions that set left for the author, not
an oversight. This is that question, answered **narrowly** — as gap item 3 itself anticipated the
answer might be — rather than left open indefinitely or answered by quietly adding a component.

**The answer is one glyph, for one meaning, not an icon set.** A padlock, inline SVG, `aria-hidden`,
rendered only beside a nav entry `AppShellNavItem.muted` marks (`src/shell/AppShell.tsx`'s own
`NavLockGlyph`) — never a general-purpose icon component other screens can reach for. Nothing else in
the console gained an icon by this amendment: text stays the console's only way to name a concept,
exactly as gap item 3 stated the case for the original closed set ("text is unambiguous and
translatable"). The lock is not text *replacing* a word — the entry's own label stays the label; the
glyph is a second, wordless channel for one fact ("this is not yours to use yet") that would have cost
real density spelled out beside all twenty-one entries of a navigation that already wraps onto a
second row on a laptop-width screen (`shell.css`'s own found-live account of that wrap).

**Why this did not need a headless library or a new dependency**, revisiting the Decision's own
"Alternatives considered" reasoning one more time: a static, decorative SVG path is not a component in
the sense Radix/React Aria/a component library would answer for — there is no focus management, no
keyboard interaction, no ARIA state machine behind a lock mark, only a shape and a translated
`aria-hidden`-adjacent hidden label. The genuinely hard parts that ADR's Context named up front
(focus trapping, `aria-describedby` wiring, combobox behaviour) are exactly as absent from this glyph
as they were from `.ago-shell__glyph`, the brand mark already drawn the identical way before this
amendment. Buying a dependency for a second hand-drawn shape would repeat the "solving a problem this
application does not have" mistake the original Decision already rejected once.

**The two bounds this glyph is held to, both enforced mechanically, not by convention:**

- **A translated, visually-hidden label**, `strings.navLockedLabel`, present in both `en.ts` and
  `ru.ts` — without it the glyph does not exist for a screen reader, and `11-13` already made an
  untranslated interface string a gate failure rather than a nit.
- **The muted text colour it sits beside is measured, not eyeballed**, the same "Contrast is measured,
  not eyeballed" rule this ADR's Decision point 5 already states for every other pair `tokens.css`
  produces: `--ago-ink-faint` at 5.42:1 on `--ago-surface`, comfortably clear of the WCAG AA 4.5:1
  floor for normal text, and `ux-gate`'s own contrast assertion (`ux-gate/lib/contrast.ts`) now
  exercises a muted, gated-navigation screenshot for the first time (`ux-gate/fixtures/screens.ts`'s
  `admin-limited-permissions`) — mechanically checked on every gate run, not merely measured once at
  authoring time.

**What this amendment is not.** It is not a reopening of "no icon set" as a general position, and the
next screen that wants a tab bar, a combobox, a date picker or a toast is still the trigger to revisit
this ADR properly (the Decision's own "The closed list will be tested" consequence, unchanged) — not
a precedent that one exception opens the door to the next one. A future reader who finds a second icon
anywhere in this console did not find it licensed by this paragraph.

`docs/design/gaps.md` pile 3 item 3 is updated alongside this amendment to record that the icon
question was answered, narrowly, rather than left as an open red block.

## Amendment (2026-09-06): the glyph is withdrawn — the meaning it marked no longer exists

`23-31`/`adr/0129` replaces `23-24`'s own muting rule (`docs/design/decisions.md` §10) with a
narrower one: muted now means "this identity could obtain the thing itself" — in practice the
calendar module, for a tenant who has not bought it — never "a colleague at this tenant could grant
it". Thirteen of the fourteen entries that glyph used to mark no longer carry a muted state at all:
they are hidden outright when the permission is missing, exactly as they were before `23-24`. The one
gate that keeps a muted state marks a *different* fact than the glyph stated — not "locked, a
colleague holds the key", but "for sale".

**The glyph is deleted, not repointed.** A padlock reads as "restricted", not "buyable", and reusing
the same shape for the opposite meaning would be a worse-than-nothing visual pun; `adr/0129`'s own
"Alternatives considered" says so directly. `NavLockGlyph` is removed, and the calendar's muted entry
carries a small visible `Badge` instead — already one of the eleven, not a new component and not a
second icon.

**So the closed set is eleven again, with no open exception.** The 2026-09-05 amendment warned that a
future reader who found a second icon in this console "did not find it licensed by this paragraph";
as of today there is no icon in the console at all. `docs/design/gaps.md` pile 3 item 3 is therefore
**re-opened** rather than closed by that amendment's own last line, because the concrete answer which
closed it no longer ships.

## Amendment (2026-09-12): the header collapses into a user menu — three glyphs, and the console's first real dropdown

`25-47` collapses the header's right side (the operator's name, the tenancy `<select>`, a visible
"Sign out" button, all three side by side) behind one circular avatar. Clicking it opens a dropdown -
GitHub's own account menu is the item's named reference - listing, in order: a non-clickable header
row (avatar, name, active tenant), an optional tenant-switcher section, Appearance, and Sign out. Two
things this ADR already governs are touched: the icon question (item 3, re-opened above) and, for the
first time, item 4's neighbour - a real dropdown menu, not a `<select>`.

**The icon question, answered a third time - narrowly again, the same shape as 2026-09-05's, not a
reopening of the general position.** Three static, `aria-hidden`, `currentColor` SVG paths
(`src/shell/menuIcons.tsx`) - a globe-shaped glyph beside the tenant switcher, a palette beside
Appearance, `logout` beside Sign out - for exactly the three rows this one menu needs, nothing else in
the console gaining an icon by this amendment. The reasoning the 2026-09-06 withdrawal turned on -
"tied to one meaning, and the meaning changed" - does not apply here the way it did to the deleted nav
lock: these three glyphs are decoration beside menu-item text that already names the same thing in
words (the same "not translated text, a second wordless channel for one fact already stated" shape),
not the sole carrier of a meaning that could shift under them later. Path data is Google's own
Material Symbols Outlined, weight 400/fill 0/grade 0, fetched verbatim from `google/material-design-
icons` on GitHub (`symbols/web/<name>/materialsymbolsoutlined/<name>_24px.svg`, `master`, retrieved
2026-09-12) - never retyped from memory, for the same reason a hand-copied colour value would be a
defect in `tokens.css`: a plausible-looking path that silently renders the wrong shape is worse than an
obviously missing one. `docs/design/gaps.md` pile 3 item 3 is updated alongside this amendment.

**The avatar answers pile 3 item 8 directly** - "Badge is the product's only representation of a
person - no avatar, no initial, no name" - with initials (`operatorInitials`, `src/auth/
operatorInitials.ts`), never a photo: nothing in this identity system carries one, so there is no
fallback state an avatar-with-image would need and this component does not invent one. Updated
alongside item 3 above.

**The harder question this amendment has to answer honestly is the Alternatives section below -
"the first real combobox, menu, or tooltip is the trigger to revisit" this whole ADR.** A dropdown
menu is exactly that trigger, and it would be dishonest to add one and say nothing. The call made
here is: not yet, and here is what "yet" would look like. What makes a menu the hard case for a
headless library to earn its keep - focus trapping, a roving-`tabindex` arrow-key protocol, submenus,
typeahead - is not what this menu does. It is one level deep, has at most nine rows, is not modal (the
rest of the header and the page stay live behind it, unlike `Dialog`), and deliberately does not claim
the ARIA `menu`/`menuitem` roles that would promise that keyboard protocol (`ShellIdentity`'s own doc
comment, `AppShell.tsx`) - it is a disclosure over a short list of ordinary, independently focusable
buttons and one `Link`, closed by a `pointerdown` listener and an `Escape` handler that together are
about fifteen lines. That is measurably smaller than adopting Radix or React Aria for it would be, and
unlike the padlock glyph this is not a one-off either - the same shape would serve a second menu
this console grows later without new code, only a new list of rows. **What would tip this call**: a
second, independent menu that needs *nested* items, or real keyboard users reporting that arrow-key
navigation is expected and its absence reads as broken (this ADR's Alternatives section already names
`aria-menu` conformance as the deciding fact, not a hunch) - either is grounds to revisit properly,
not to quietly grow a second hand-rolled menu with different behaviour from this one.

## Amendment (2026-09-12): the twelfth component — a tooltip, exactly where this ADR said one would go

`25-54` moves eight standing explanatory paragraphs out of permanent inline text in the three-panel
workspace and behind a `(?)` trigger, hover/focus-revealed. Seven of the eight strings this item's
own investigation named were real; the eighth (an explanation near `ChannelIdentitiesPanel`'s own
"Связанные каналы" title) does not exist in the code today and nothing was invented to fill it —
recorded here rather than left silent, since the item's own Verified section had assumed it did.

**This grows the closed set itself, not just the icon exception two amendments above narrow again
and again.** This ADR's own Alternatives section named its trigger in so many words: *"the first
real combobox, menu, or tooltip is the trigger to revisit this ADR."* A tooltip earns a twelfth,
shared component rather than one screen's own local markup for the same reason the two icon
amendments above stayed narrow instead of opening a general system: this item alone gives it seven
call sites across three panels (`ConversationList` twice, `ConversationPage`, `Thread`,
`ConversationNotesPanel`, `ConversationOutcomePanel`, `VisitorPanel`), and a hover/focus-triggered
popover with real keyboard and touch behaviour is exactly what a copy-pasted `<span>` per call site
would drift on — nobody owning the interaction is the failure mode this ADR's own Alternatives
section already names for a component like this.

**Still hand-rolled, the same call the dropdown-menu amendment above already made and for the same
reason**: the hard parts a headless library buys — focus trapping, a roving-`tabindex` protocol,
submenu/typeahead — are not what a tooltip needs. It is not modal, holds no focus hostage, and has
exactly one interactive element. Native `title` was the real alternative and loses on the request
that raised this item: it never fires on keyboard focus, cannot be styled to this console's own
tokens, and cannot be measured for contrast the way `tokens.css` measures every other pair — a
console that already gates on WCAG 1.4.11/2.5.8 elsewhere is exactly the case `title` is wrong for.

**The trigger glyph is a plain `"?"` character, not an icon** — deliberately not reaching for either
of the two icon exceptions above, both of which are scoped narrowly to one meaning each and say so
in their own text. A text glyph costs nothing, needs no path data fetched from anywhere, and matches
this console's own founding argument for closing the set at eleven in the first place: text is
unambiguous and translatable.

**What this does not attempt**: viewport-collision detection (the bubble always opens below,
left-aligned to the trigger) or multi-line reflow beyond a fixed `max-width`. Every call site this
item adds lives inside the three-panel workspace's own bounded columns, never near a viewport edge
at this console's supported widths — a positioning library would be solving a problem that does not
exist yet, the same shape this ADR's own "Alternatives considered" already rejects a dependency for
elsewhere. The trigger to revisit this specific limit is a real report of a clipped bubble, not a
hunch. `docs/design/gaps.md` pile 3 item 4 ("no tooltip and no popover") is closed by this amendment.

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
