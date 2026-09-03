# Mobile navigation becomes a drawer, in both consoles

- **Stage**: 11
- **Status**: half done — `ago-console` shipped 2026-09-03 (`ago-console#90`). `ago-calendar-console`
  has **not** got a drawer; `15-12` closed its overflow with two CSS rules instead, so its nav wraps
  onto a second row rather than collapsing. `ago-calendar-console#25` carries that half.
- **Raised by**: the author, 2026-09-02, after `15-11`'s gate made the current state measurable.
- **Touches**: `ago-console`, `ago-calendar-console`. Deliberately **not** a shared component — see
  Open questions.

## What is being asked for

Replace the horizontal navigation bar at mobile widths with a hamburger button opening a panel that
slides in from the left, listing the items in a column.

## Why, with numbers rather than taste

The horizontal bar does not fit, and this is now measured rather than felt:

- **`ago-console` builds fifteen navigation items** for a tenant holding `site:configure`
  (`shell/consoleNav.ts`): conversations, all conversations, search, four analytics reports and eight
  settings screens. Fifteen labels have never fitted a 375px bar, and they do not comfortably fit a
  1280px one either — which is the part worth noticing, because it means this is not only a mobile
  fix.

  It was fourteen when this item was written, on 2026-09-02. `10-06` added `/settings/install` the
  same day. That is the argument for the item rather than against it: the count is not a fixed
  property being worked around, it grows with every tenant-facing screen, and each one lands in a bar
  that already does not fit.
- **`ago-calendar-console` has six**, hardcoded as `<NavLink>`s in `App.tsx`, and **no `@media` rule
  anywhere in its stylesheet**. `15-11`'s gate found all eight of its screens overflowing at 375px
  (`ago-calendar-console#22`); the nav strip is one of the contributors, visible in the gate's own
  screenshots as a clipped final item.
- The same clipping is visible in `ago-console` on the live deployment — the bar ends mid-word on
  `Analytics`.

So both consoles are affected, for the same reason, with different severities.

## What makes this cheap in one console and not the other

**`ago-console`'s navigation is already data.** `buildTenantNavItems` returns `AppShellNavItem[]`
(`to`, `label`, `end`), permission-filtered, consumed by `AppShell`. A drawer is a second renderer over
the same array — no route knowledge, no per-item work.

**`ago-calendar-console`'s is markup.** Six `<NavLink>`s written inline in `App.tsx`. Getting a drawer
there means first giving that console the same shape, which is small but is real work that
`ago-console` does not need.

That asymmetry is the whole scoping story, and it is why this is one decision and two issues rather
than one change.

## Scope

- A hamburger control and a left drawer at mobile widths in both consoles: items in a column, the
  current item marked, dismissable by the backdrop, by `Escape`, and by choosing an item.
- **Keyboard and focus behaviour, because a drawer is where this is usually skipped**: focus moves
  into the panel on open, is trapped while it is open, and returns to the hamburger on close.
- `ago-calendar-console`'s navigation becomes a data list first, matching `ago-console`'s shape.
- The `15-11` gate must stay green in `ago-console` and must **improve** in
  `ago-calendar-console` — the nav should stop being one of `#22`'s overflow contributors. Whether the
  other contributors (wide tables) are fixed here is out of scope; this item is not allowed to claim
  `#22` closed on its own.

## Out of scope

- **A shared component between the two consoles.** They have no shared package, and their design
  layers are 84 tokens against 5. Building the first shared component under launch pressure, on the
  weaker of the two foundations, is how a shared layer gets shaped by whichever console happened to go
  first. See Open questions.
- The wide tables that also overflow (`ago-calendar-console#22`).
- Desktop navigation in `ago-console`, even though fourteen items is a real problem there too. Named
  in Open questions rather than silently widened.

## Done when

- [ ] Both consoles show a hamburger and a left drawer at 375px, with items in a column and the
      current one marked. — **`ago-console` only.** The calendar console's nav wraps instead.
- [x] The drawer is dismissable three ways — backdrop, `Escape`, choosing an item — each proven by a
      test rather than by eye.
- [x] Focus enters the drawer on open, is trapped while open, and returns to the hamburger on close.
      This is the half that gets skipped, so it is a Done-when and not a note. Proven in a real
      Chromium rather than jsdom, whose `<dialog>` shim has no focus semantics to assert against —
      the existing precedent was to accept that gap, and `ago-console#90` closed it instead.
- [x] `ago-console`'s `15-11` gate is still green at both viewports — 23 passed, 5 skipped, exit 0.
      The skips are the new drawer tests' desktop counterparts, which correctly skip because above
      40rem the hamburger has no rendered box.
- [x] `ago-calendar-console`'s nav no longer contributes to horizontal overflow — demonstrated by the
      gate's own measurement, with the remaining overflow (if any) attributed to something else.
      Closed by `15-12` **without** a drawer: `flex-wrap` on the nav row. That run also found the
      overflow was *two* independent causes, the second being a seven-column table wider than its
      panel, which a nav-only fix would have left failing on five screens.
- [ ] `ago-calendar-console`'s navigation is a data list, not inline markup.
- [ ] No screen becomes unreachable on a narrow viewport — including the analytics and settings items
      that are hardest to reach today. — true in `ago-console`; unverified in the calendar console,
      where a wrapped two-row nav is reachable but was not tested for it.

## What shipped, and what the split means

`ago-console`'s nav was already a permission-filtered `AppShellNavItem[]`, which is why this repository
was always the cheap one: the drawer is a **second renderer over the same array**, not a second source
of navigation. The property worth having is that the bar and the drawer cannot disagree about what a
tenant may see — a disagreement there is a permission bug wearing a layout costume — and it is proven
by making the drawer render one item the bar does not and watching two tests fail.

It reuses `Dialog`'s native `<dialog>`/`showModal()` through a `variant="drawer"` prop rather than
adding a twelfth component to `adr/0030`'s closed set, so focus trapping, focus restoration and
`Escape` come from the browser instead of from new code.

**The calendar console did not need a drawer to stop overflowing**, which is the honest reason its
half is still open rather than an oversight: `15-12` had to fix that overflow anyway, and two CSS
rules did it. Its nav is still six inline `<NavLink>`s, so the data-list box stands, and a wrapped
two-row bar on a phone is a worse answer than a drawer — just no longer a *broken* one.

## Open questions

- **Should `ago-console` use the drawer at every width, not only mobile?** Fourteen items is a lot of
  horizontal bar on a 1280px screen too. A single navigation pattern is simpler to own than two, and
  the author's own framing — these consoles are daily tools now, not an admin panel — argues for
  deciding this deliberately rather than defaulting to "desktop keeps the bar".
- **When does the shared design layer happen?** This is the second item in a week to be shaped by the
  84-versus-5 gap (`15-11` was the first). The gap is not this item's to close, but it is now visibly
  costing something on each pass.
- **Does the calendar console's booking widget need the same treatment?** It has its own surface and
  its own navigation question, and nobody has looked.
