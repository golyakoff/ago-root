# A rendered UX gate, and the screenshots that fall out of it

- **Stage**: 15
- **Status**: ready
- **Why here**: this is release quality — the class of defect that ships green and is found by a human
  afterwards. Stage 15 is where "the deployment stops being a thing it would be acceptable to lose"
  lives, and shipping an unusable screen to a paying tenant is the product-facing half of that.

## Where this came from

Three defects reached the live deployment, were reported healthy by tests, `smoke.sh` and a post-deploy
check, and were then found by the author by hand:

1. **Message sending from the widget was broken** — the product's core path.
2. **An input field rendered one character wide on mobile.**
3. **An error message was dark grey on dark blue**, effectively invisible.

Number 1 belongs to the golden-path item. **Numbers 2 and 3 are this one**, and the reason they are
worth a mechanical gate rather than more careful looking is that both are *computable*: an element's
rendered width and a foreground/background contrast ratio are measurements, not opinions.

The project already learned the shallower version of this in `5-18` — SignalR *negotiate* succeeded for
the entire time the operator console could not connect, and `smoke.sh` carries the sentence "12/12
stayed green through a total product outage". Rendered-UI defects are the same shape one layer up: every
unit test passes while the screen is unusable.

## What was checked before scoping, and what it changed

- **`ago-console` has a real design layer**: `src/design/tokens.css` with **84** `--ago-*` custom
  properties, plus `theme.ts`, `theme.test.ts` and a `ThemeToggle`. `adr/0030` was actually built.
- **`ago-calendar-console` has five**: `--accent`, `--danger`, `--ink`, `--line`, `--muted`,
  unnamespaced. **There is no shared package**; each console carries its own copy of whatever it has.
- Both consoles run **vitest + jsdom**. Neither has a browser-driving test tool.

That last pair of facts changed this item's shape. **jsdom has no layout engine**, so it can measure
neither width nor rendered colour — an overflow assertion written there would pass on anything. And a
contrast check built on *token pairs* would be near-worthless for the calendar console, because its
colours are not in tokens at all; they are scattered through components.

So the check has to read **computed styles from a really rendered page**. That form catches
grey-on-blue whether or not the colour came from a token — which is exactly the defect that shipped —
and it works on both consoles today, without waiting for a design system.

## Scope

- **A rendered-page test run** in each frontend repo (`ago-console`, `ago-calendar-console`,
  `ago-widget`), at **two viewports**: 375×812 and 1280×800. Both, because four of the author's own six
  named surfaces are mobile.
- **Three assertions**, all measurements:
  - **No horizontal overflow**: `document.documentElement.scrollWidth` must not exceed `innerWidth`.
    Verified by hand on the live widget while writing this — it currently passes (375 = 375), so the
    check starts from a known-good baseline rather than a red one.
  - **No interactive element rendered unusably small** — a stated minimum for inputs and buttons, so
    "one character wide" is impossible to ship. The widget's composer is currently 150×40, which is
    tight but fine; the threshold must be chosen to accept that and reject the reported defect.
  - **Contrast meets WCAG AA**, computed from the *rendered* foreground and background of text nodes,
    not from a token table.
- **Screenshots are an output of the same run**, at both viewports, written as build artifacts. This is
  the second purpose and it is not decoration: the author cannot see a third of what ships, and the
  digest that fixes that currently has no pictures in it.
- **Authentication without a login form.** The run injects a token directly rather than driving
  Keycloak's UI. This is how the run stays reproducible in CI — and it is also why an AI session can
  produce these screenshots at all, since typing a password into a form is something it does not do,
  even with the demo credentials the demo page publishes openly.
- **Wired into CI** on every push, failing the build on a violation.

## Out of scope

- **Visual-regression snapshots** (compare-to-golden-image). Much higher maintenance, and it answers a
  different question — "did this change?" rather than "is this usable?". The three assertions above are
  absolute, so they need no baseline to drift.
- **A shared design system between the two consoles.** The 84-versus-5 divergence found while scoping
  this is real, is the author's own stated concern, and is its own item — see Open questions.
- **The golden path** (a visitor's message reaching an operator and back). Separate item; this one is
  about how screens render, not about whether the product works.
- Any change to how the consoles look. This item measures; it does not redesign.

## A dependency worth stating plainly

**`ago-calendar-console` cannot be screenshotted from a deployment**, because AGO Calendar is not
deployed (`20-20`). It *can* be screenshotted here, because this runs against a build from source with
seeded data rather than against the live stand.

That is a real and immediate win: it puts eyes on the schedule-template, workers and re-cut screens —
about a third of the last week's work, currently invisible — **without waiting for `20-20`**.

## Done when

- [ ] The three assertions run at both viewports in all three frontend repos, and fail the build when
      violated — each proven to fail first, by introducing the defect it is meant to catch (an
      overflowing element, a one-character input, a low-contrast pair) and watching it bite.
- [ ] The reported historical defects are specifically covered: a one-character-wide input and a
      dark-grey-on-dark-blue message would both now fail.
- [ ] Screenshots for both viewports are produced as CI artifacts on every run, named so a human can
      tell which screen and which viewport without opening them.
- [ ] No step in the run types a password into a form.
- [ ] The next digest embeds screenshots taken by this run rather than by hand.
- [ ] `docs/conventions/testing.md` gains this level, since it is a new one — neither unit nor
      integration nor the existing e2e shape.

## Open questions

- **A shared design layer between the two consoles** is the author's own stated goal ("consistent,
  DRY, reusable when we build Android and iOS"), and the measurement above makes the gap concrete: 84
  tokens against 5, with no shared package. Worth its own item, and worth deciding *what* is shared —
  a token file is reusable by a mobile app, React components are not, so the sharable unit is probably
  the tokens and the decisions, not the components.
- **Which screens** each run covers. Every route is slow and mostly redundant; a named list is fast and
  goes stale. Probably: the author's six named surfaces first, extended when a screen earns it.
- **Whether the widget's 150px composer is acceptable** at 375px, or whether that is the same defect
  in a milder form. It is usable, but it is the narrowest thing on the surface the product is named
  after.
