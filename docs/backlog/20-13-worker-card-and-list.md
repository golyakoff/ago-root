# The worker card and the worker list: real name fields, activity, timestamps, deletion

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-01-domain-model-and-persistence.md` (done) — the `Worker` aggregate this widens.
  `20-06-console-and-booking-widget.md` (done) — the console screen this replaces the add-only form on.

## Why this, and why now

The first of the tenant's own scheduling tools, named ahead of the first live client. A tenant cannot
actually keep a staff list from the console today: `POST /workers` creates a worker and **nothing can
ever change one afterwards** — no rename, no deactivation, no deletion — and the only "list" is a
nested array inside `GET /configuration` rendered as an unstyled `<li>`. `Worker.Deactivate()` and
`Worker.Reactivate()` exist in Domain, are tested, and have never been reachable from outside the
process.

Ten workers is a lot for this product, by the author's own measure. So no server-side search, no
paging, and not even a front-end filter: one table with every row in it.

## What already exists, checked before scoping the rest

- `Worker` carries `Id`, `TenantId`, `DisplayName`, `IsActive`, its one calendar membership and its
  service offerings, with `Create`, `Rename`, `Deactivate`, `Reactivate`, `JoinCalendar`, `Offer`.
- **`Worker` has neither `CreatedAt` nor `UpdatedAt`.** `BookingCalendar` has a `CreatedAt`; the worker
  never got one. Both are new columns, and `UpdatedAt` is new behaviour, not just a column.
- `POST /workers` is the *only* worker endpoint (`ConsoleEndpoints.cs`). No `GET`, no `PUT`, no
  `DELETE`.
- **`Worker`'s own doc comment argues against deletion**: "Deleting a worker who has bookings is not a
  thing this product should offer." This item does not overrule that — it narrows it, below.

## Decided: the display name is a stored column with an override flag, not a computed property

Four name fields — `LastName` (required), `FirstName` (required), `MiddleName` (optional),
`DisplayName`. `DisplayName` is derived as first-name-space-last-name with whitespace collapsed, and
**stops** being derived the moment a human types one of their own.

Two shapes were weighed:

- A nullable `CustomDisplayName` with a computed `DisplayName => CustomDisplayName ?? Derive(...)`.
  No flag to keep in sync — but `DisplayName` stops being a column, and every read model that selects
  it (the public booking surface, `20-15`'s slot table, `20-12`'s contacts report) would have to
  reproduce the derivation in SQL. That is one rule written in three languages, which is three places
  for it to disagree.
- **Chosen**: `DisplayName` stays a real, always-populated column, and a `DisplayNameIsCustom` flag
  records whether a human set it. `Rename(first, last, middle, now)` recomputes `DisplayName` only
  while the flag is false; `SetDisplayName(value, now)` sets it and raises the flag. SQL keeps
  selecting one column, and "если ввели руками, а потом меняют Имя или Фамилию — значение уже не
  рассчитывается" is literally that method's `if`.

## Decided: deletion is allowed only for a worker nobody has ever booked

A worker with any `Event` in `PendingConfirmation`, `Booked` or `NoShow` — past or future — cannot be
deleted, and the console offers deactivation instead. That is what the aggregate's own doc comment
already argued for, and it is what keeps a completed or cancelled visit auditable: a customer's
history should not disappear because the stylist left.

A worker with only `Available` rows, or none, is deleted outright, taking those rows, his
working-hours rules, his calendar membership and his service offerings with him. None of that is
anybody's history.

**The check runs inside the same transaction as the delete**, not as a read followed by a delete —
otherwise a booking that lands between the two is destroyed silently, which is precisely the case the
rule exists to prevent.

## Scope

- `Worker` gains `LastName`, `FirstName`, `MiddleName`, `DisplayNameIsCustom`, `CreatedAt`,
  `UpdatedAt`. Every mutator takes `DateTimeOffset now` and sets `UpdatedAt`: Domain must not read a
  clock (CLAUDE.md rule 2), so the instant arrives as an argument, the same way `Event` and
  `BookingCalendar` already receive it.
- A migration adding the columns, with `CreatedAt`/`UpdatedAt` backfilled **from the row's own id** —
  `WorkerId` is a UUIDv7 minted by `IIdGenerator`, so it carries its own creation instant, and
  `20-12`'s migration already relied on that ordering property. Inventing `now()` for a row created
  last week would be a fabricated timestamp in a column a tenant reads.
- `GET /workers`, `GET /workers/{id}`, `PUT /workers/{id}` (names, display name, activity),
  `DELETE /workers/{id}` — all gated on `Permission.CalendarConfigure`, all tenant-isolated.
- Console: a workers table — display name, activity, created, updated, and per row: open card, open
  schedule, open slots, delete behind a confirmation. The schedule and slots links land in `20-14` and
  `20-15`; until then they are absent, not broken.
- Console: one worker card component used for both create and edit. The display-name field prefills
  with the derived value and only marks it custom when the human actually edits it.

## Out of scope

- The schedule template itself — `20-14`.
- The materialised-slot view the card links to — `20-15`.
- Services and calendar membership: `Offer` and `JoinCalendar` keep the surface they have.
- Moving a worker to a different calendar. v1 is one calendar per worker
  (`WorkerCalendarLimitException`), and that limit is not this item's to lift.

## Done when

- [ ] Creating a worker with only фамилия and имя produces a display name equal to "Имя Фамилия" with
      collapsed whitespace — proven by a test whose input carries stray spaces.
- [ ] Editing фамилия *after* a human typed a display name leaves the display name untouched; editing
      it *before* recomputes it. One test each, on the same worker.
- [ ] A worker with a `Booked` event cannot be deleted and the API says why; a worker with only
      `Available` events can be, and his slots, rules and joins go with him — with the booking check
      proven to run inside the delete transaction.
- [ ] `UpdatedAt` moves on every mutation and `CreatedAt` never does, proven against a fake clock.
- [ ] The console lists every worker in one table, opens a card for create and for edit, toggles
      activity, and deletes behind a confirmation.
- [ ] Another tenant's worker is invisible to all four endpoints, proven by a test.

## Open questions

- **Backfilling `LastName`/`FirstName` for workers that already exist.** They have only a display
  name, and the new fields are required. Splitting on the first space guesses at a name; leaving them
  empty leaves rows that violate the rule the API enforces for every new row. The live demo tenant is
  the only real data today, so the cheap answer — backfill `LastName` from the whole display name,
  `FirstName` empty, `DisplayNameIsCustom = true`, and let the console show it as needing a
  correction — may simply be right. Decide when implementing, and say which was chosen.
