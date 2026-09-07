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

- [ ] The reading is chosen by the author and recorded where a reader will find it.
- [ ] A response missing a field renders something a person can tell apart from an empty account.
- [ ] Whichever screens are left uncovered are named, rather than left to be discovered.
