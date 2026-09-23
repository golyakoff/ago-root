# 26-74 · «Показы телефонов» — there is no read-back of who revealed a phone

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading `ago-console/src/pages/CalendarPhoneRevealsPage.tsx` and
  `ago-console/src/api/calendarApi.ts` against `ago-android` `main` at `b099282`, with the approved
  mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)'s own
  `MyNumbers -- "⋮ · calendar:configure" --> Reveals`.

## Found

The fifth of the five `26-58` decided to port, and the only one that is a **record of what people
did** rather than a count of what happened. `26-53` gives the phone the ability to reveal a masked
number and writes an audit record naming Android as the surface (`"AndroidContacts"`). Nothing on the
phone can read that trail back — including the record the phone itself just wrote.

That is why this is its own item and not part of `26-53`: performing a reveal and reading a history
of reveals already performed are two promises, each of which lands green on its own (rule 15).

## What is actually true today, confirmed against real code

- `ago-console/src/App.tsx:538` → `CalendarPhoneRevealsPage`. It keeps its `/calendar/` address
  while living under Аналитика in the nav — `25-17` moved the entry deliberately and left the route
  alone (`consoleNav.ts:174-186`), and its gate is exactly **`calendar:configure`**
  (`consoleNav.ts:195-197`), independent of `isAdmin`, unlike the four `site:configure` reports.
- The read is `GET /contacts/phone-reveals` on the **calendar** API (`calendarApi.ts:715-726`),
  keyset-paged: `before` is the last `id` of the previous page, `undefined` for the first, plus an
  optional `limit`. The page is `{ items, nextBefore }` where `nextBefore` is `null` once the oldest
  row is reached (`calendarApi.ts:405-410`).
- **A row is four fields and no names** (`calendarApi.ts:397-403`): `id`, `occurredAt`,
  `customerId`, `operatorId`, `surface`. The console renders both ids as eight truncated hex
  characters and the surface verbatim (`CalendarPhoneRevealsPage.tsx:125-145`); `occurredAt` renders
  as a clock time with the absolute timestamp on hover.
- **Individual reveals, never a per-operator count.** That is a stated restraint, server-side and in
  the page's own doc comment (`:24-27`, quoting `decisions.md` §5: reveal counts belong in an audit
  view, never in the report a person is judged on).
- **Forbidden and empty must look different** (`:104-114` vs `:159-161`) — the item that built this
  screen made that its own Done-when, because "renders nothing" is indistinguishable from a
  genuinely empty audit trail.
- **"Calendar not configured" is a third, real state** (`:116-122`): the console treats
  `config.calendarApiBaseUrl === null` as a rendered message, not a failure. `26-48` already added
  the app's nullable second base URL for exactly this, so this screen inherits it rather than adding
  a fourth state of its own.
- Paging is a `Load more` button while `nextBefore !== null` (`:167-173`).

### What the mockup does and does not say

The mockup names this destination («Показы телефонов») and its gate as a graph node and an overflow
edge, and **draws no frame for the screen itself**. `scope-inventory.md` §5 calls it **as-is**, and
the data shape agrees: four short fields per row is already a phone-shaped list, so this is the one
of the five that does not need a desktop table taken apart — it needs a card list.

## Scope

One promise: **«Показы телефонов» shows this tenant's reveal audit trail, newest first, paged.**

1. `getPhoneReveals` on the `BookingsApi` port `26-48` introduces (the calendar-API port), taking
   the optional keyset cursor and limit — no new base URL, no new adapter class if the existing one
   fits.
2. A new entry in Аналитика's overflow («Показы телефонов»), gated **`calendar:configure`** — not
   `site:configure`, so an operator may hold this entry and none of the other four, or the reverse.
   The menu `26-70` builds must already treat its entries' gates independently; this is the item that
   proves it does.
3. One level deep with the same `BackHandler` contract `26-70` establishes.
4. **A card list, one card per reveal**: when, which customer, which operator, which surface. Ids
   render as this app already renders every identifier (`IdentifierText`), never as an invented name.
5. **Keyset paging**, `nextBefore` driving either a `Load more` control or infinite scroll — the
   cursor semantics do not change either way.
6. **Three distinct states, all reachable**: forbidden (no `calendar:configure`), calendar not
   configured (no base URL), and a genuinely empty trail. None of them may render as any other.
7. Every other failure is a refusal with a retry, never a raw exception class name (`26-59`).

## Out of scope

- **The overflow menu itself** — `26-70`.
- **Revealing a phone number** — `26-53`. This screen reads; it never unmasks anything, and it never
  shows a phone number at all (the trail does not carry one).
- **Any aggregation.** No per-operator count, no "most reveals this week". The console refuses this
  deliberately and so does the phone.
- **`/calendar/customer-merges`**, the other calendar audit trail. Same shape, different item, not
  filed here.

## Done when

- [ ] An operator holding `calendar:configure` reaches «Показы телефонов» from Аналитика's overflow
      and sees the tenant's reveal trail, newest first.
- [ ] An operator holding `site:configure` but **not** `calendar:configure` sees the other overflow
      entries and not this one; an operator holding only `calendar:configure` sees this one and not
      the others.
- [ ] Forbidden, "calendar not configured" and an empty trail each render as themselves and are
      visibly different from one another.
- [ ] Paging past the first page works, and the control disappears once the oldest row is reached.
- [ ] No name is invented for a customer or an operator, and no phone number appears anywhere on the
      screen.
- [ ] A reveal performed from the phone (`26-53`) appears in this list with its Android surface name.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device, in both light and dark, against a trail with more than one page and
      against an empty one.
