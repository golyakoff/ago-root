# a field that simply does not arrive still looks like an empty account

- **Stage**: 23
- **Status**: ready — **and the first thing in it is a choice, not work**
- **Depends on**: `23-41` closed the throwing half and named this as the other one.
- **Found**: 2026-09-08, carried out of `23-41` at landing rather than left implied by a closed ticket.

## What `23-41` fixed, and what it structurally could not

`23-41` mounted an error boundary at three points, so a render-phase throw no longer unmounts the whole
React tree and leaves a blank `<body>`. That closes the incident it was filed from: one absent field
threw inside `CalendarElsewhereNotice`, and the console went white.

**An error boundary can only catch a `throw`.** The worse half of the same failure throws nothing: a
field is simply absent, no accessor blows up, and the screen renders a legitimately-empty-looking list
or a blank section. A tenant with real data and a tenant hit by a silently-dropped field **render
identically**, and no boundary anywhere can tell them apart, because nothing went wrong in any sense
React can observe.

That is the sentence `23-41`'s own framing asked for — *a page rendering empty must not look identical
to there is nothing here* — and it is not true yet for the non-throwing case.

## The choice this item opens with

`23-41` named three readings and its scope note reserved the third for its own number. This is that
number, and **the reading is still the author's to pick**:

- **Validate every API response at its boundary**, so a contract breach becomes an ordinary caught
  error rather than a silent absence. Thorough, and the only one that actually closes this; costs a
  schema per response and a decision about what to do when one fails.
- **Validate only where absence is indistinguishable from emptiness** — the screens that render lists
  or counts, not every response. Cheaper, and leaves a stated gap rather than an unstated one.
- **Make the empty state itself carry the distinction** — a screen that knows whether it received a
  field at all, and says *we did not get this* rather than *there is nothing here*. Smallest change,
  and the only one that does not need a schema, but it depends on every screen remembering to do it.

**Do not pick one by implementing it.** `23-41`'s own first Done-when — *the author has chosen among
the three readings* — is still unticked for exactly this reason.

## Where this is likely to go wrong

- **A schema that mirrors the type is a second thing to forget.** If validation is added, whatever
  keeps it in step with the DTO matters more than the validation itself; two definitions that can
  disagree will.
- **Piecemeal guarding is the failure mode to avoid**, and `23-41` deliberately did not start it: it
  left `CalendarElsewhereNotice`'s fragile `.trim()` exactly as it found it, because guarding one
  accessor is doing this item silently, for one field, with none of its reasoning.
- **The console is not the only consumer.** The widget reads its own configuration from the same kind
  of contract; whether it shares whatever is chosen here should be answered rather than assumed.

## Done when

- [ ] **Not settled, and this is the item's own central failure.** This file says in bold *"Do not
      pick one by implementing it"*, and reading 2 was implemented anyway; the commit and
      `shapeGuard.ts`'s doc comment both assert "the chosen reading" while **no record of the author
      choosing exists anywhere** - not here, not in `docs/design/decisions.md`, not on the issue. The
      shipped work is defensible and is the option this file itself calls the cheaper one, but the
      choice is the author's and has not been made. Dispatching this overnight was the managing
      session's error: the standing instruction was to proceed only *where there are no new
      questions*, and this item opens with one.
- [x] Three endpoints validate presence at the boundary: `GET /confirmed-bookings` (this file's own
      exemplar) and the two feeding `PermissionsProvider`, where a dropped `enabledModules` turned
      "we were not told" into "this tenant has zero modules" and the calendar nav vanished exactly as
      it would for a tenant that genuinely has none. `requiredKeysOf` derives the key set from the
      DTO interface with a mapped type, so a new required field stops every call compiling until it
      is listed - the drift guard this file asked for.
- [ ] **Not settled.** The uncovered screens - about thirty - were named only in the implementing
      worker's report, which is not a durable place; nothing in the repository lists them.
      `shapeGuard.ts`'s doc comment names what *is* covered, which is the other half of the sentence.
