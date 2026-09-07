# one missing field from one API renders an empty page, everywhere in the console

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: the shape is a real choice and this item **states it as a question**, because "what
  should a console do when a backend breaks its own contract" is not a decision to make by writing code.

## What happened, and it was found by accident

While landing `23-31` the ux-gate failed on one screen. The cause was not the navigation change: two
different APIs answer `/api/v1/me/tenancies` — `Ago.Chat.Api` with `{siteId, siteName}` for the
shell's shop picker, and `Ago.Calendar.Api` with `{tenantId, tenantName}` for
`CalendarElsewhereNotice`. The gate serves both from one origin, and its stub matched on pathname
alone, so the calendar's reader received the chat's body.

`tenantName` was then `undefined`, `tenantName.trim()` threw during render, and **the entire
application rendered an empty `<body>`**. No error page. No partial screen. No message. A blank white
rectangle where the console used to be.

The gate fixture is fixed (`23-31`). **This item is about the other half**: one absent field in one
response from one endpoint can currently blank the whole console, and nothing in the product limits
the blast radius.

## Why this is not merely a test-fixture story

`CalendarTenancy.tenantName` is typed `string` and documented as *possibly empty, always present*, so
the server that broke the contract here was a fixture rather than a real deployment. That is exactly
what makes it worth an item rather than a shrug:

- Two products are deployed independently and versioned independently (`adr/0012`,
  `architecture/repositories.md`). A console built against a newer calendar contract, or a calendar
  rolled back, is an ordinary Tuesday, not a hypothetical.
- The failure is **maximally silent**. A tenant sees a blank page and has nothing to report but
  "it is broken". We would see nothing at all — no request failed, no status code was wrong.
- The blast radius is the entire application, not the component that read the field.

## The question, which is the author's

**Where should the boundary be, and what should a viewer see behind it?** Three readings, and this
item deliberately picks none:

1. **One error boundary at the shell.** Cheapest. Turns a blank page into "something went wrong on
   this screen" and keeps the navigation usable. Says nothing about *what*, and one boundary means one
   broken component still takes the whole page.
2. **A boundary per route, under the shell.** The navigation and the header survive, and only the
   screen that failed is replaced. More components to place, and every future screen has to remember
   to sit inside one — the kind of rule that holds for a year and then does not.
3. **Validate at the API boundary instead.** Each `*Api.ts` checks the shape it was promised and throws
   a typed error the existing `catch` already handles, so a contract breach becomes an ordinary error
   state rather than a render crash. The most honest, and the most work: it is a decision about every
   response type in two products, not one component.

They are not exclusive — 1 or 2 bounds the damage, 3 removes this class of cause. **What is not
acceptable is what exists now**, which is that the answer depends on where the bad field happened to
be read.

## Also worth deciding, and smaller

**Should the two APIs keep sharing `/api/v1/me/tenancies`?** They answer for different things and
return different shapes. `calendarTenanciesApi.ts`'s own doc comment explains why the calendar's route
sits outside its `/api/v1/console/*` prefix — it answers for the identity, not for a tenant — and that
reasoning is sound. But the collision it produces is real enough to have blanked a page once, and it
will produce the same trap for the next fixture, the next proxy rule and the next gateway route.

## Done when

- [~] The author has chosen among the three readings above, and the choice is recorded.
      **Still the author's, and deliberately not picked by implementing one.** `23-41` shipped readings 1 and 2 — an error boundary that bounds the damage — because that is what the incident needed and what its own scope note allowed. Reading 3 is carried out to `23-99`, which opens with this same choice rather than assuming it.
- [x] A component that throws during render no longer blanks the whole console — asserted by a test
      Proven by mutating `getDerivedStateFromError` to record nothing: 10 tests across 3 files fail. `ago-console` `feat/23-41-error-boundaries-v2`.
      that throws on purpose, not by inspection.
- [~] The viewer is told something true and something actionable, in their own language.
      **Only for the throwing case.** A boundary can catch a `throw`; a field that is simply absent throws nothing, so a screen rendering a legitimately-empty list is still indistinguishable from a real empty account. That half is `23-99`, and saying so is the point of not ticking this.
- [ ] Whether the two `/api/v1/me/tenancies` routes stay as they are is answered either way.

## Out of scope

- Making every API response validated. That is reading 3 and it is its own item if it is chosen.
- The gate fixture itself, already fixed in `23-31`.
