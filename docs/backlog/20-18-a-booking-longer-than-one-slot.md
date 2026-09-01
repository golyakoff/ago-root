# A booking longer than one slot: consecutive slots claimed as one

- **Stage**: 20
- **Status**: ready
- **Depends on**: `20-14-worker-schedule-template.md` — the explicit slot length that creates this
  problem, and whose interim "not offered" rule this item removes.

## Why this, and why now

`20-14` makes slot length an explicit per-worker number, which is what the tenant asked for. It also
breaks a guarantee that used to hold by construction: while the length was *derived* from the longest
service a worker offers, every service necessarily fitted in one slot. With an explicit 30-minute
grid, a 90-minute service does not fit at all.

`20-14` ships an honest stopgap — such a service is simply not offered — and that stopgap is
crippling for a real shop: 30/60/90-minute services on a 30-minute grid means only the 30-minute one
is sellable. **This item is queued immediately after `20-14` for that reason**, not as a nice-to-have.
The author's own resolution: a 90-minute service takes three consecutive slots as one booking.

## What already exists, checked before scoping the rest

- **`Event` *is* the booking.** One row carries `CustomerId`, `ServiceId`, `Status`,
  `ConfirmationDeadline` and the instants. There is no separate booking entity.
- The claim is `BookingStore.TryBookAsync`'s single-row
  `UPDATE events SET status = 'PendingConfirmation' ... WHERE id = @id AND status = 'Available' AND starts_at > @now`,
  whose rows-affected count is the verdict and whose arbiter is Postgres (`adr/0059`). Nothing about
  that mechanism is wrong; it is simply written for exactly one row.
- `adr/0049`'s exclusion constraint forbids overlapping event rows for one worker, so a run of slots
  is by construction non-overlapping and ordered.
- There is a real `Ago.Calendar.Concurrency.Tests` project (17 tests) — the losing-race case belongs
  there, not in a unit test that simulates a race.

## Decided: a booking becomes a group of consecutive rows, claimed in one statement

**ADR-0086, amending `adr/0059`.** The claim generalises from one row to N:

```
UPDATE events SET ... WHERE id = ANY(@ids) AND status = 'Available' AND starts_at > @now
```

with the rows-affected count required to equal `@ids.Length`, and the transaction rolled back
otherwise. `adr/0059`'s whole argument survives — still one statement, still Postgres as the arbiter,
still no lock invented over an interval — it just arbitrates a set instead of a singleton. Two
customers racing for overlapping runs cannot both win, because at least one shared row can only be
updated once.

**"Consecutive" is computed server-side, never sent by the client.** Given the slot the customer
picked and the service they chose, the server walks that worker's rows on that business-local day in
start order, requiring each next row to begin exactly at the previous row's end plus the worker's
buffer. A client that could name three arbitrary ids could claim three unrelated times as one
booking.

## Decided: the buffers inside a run belong to the booking

*(Author's own clarification, 2026-09-01.)* A run's span includes the buffers between its slots, and
those buffers are consumed by that booking rather than left to anyone else. With a zero buffer the
slots are simply adjacent, which is the degenerate case of the same rule.

Nothing needs to be stored to make that true: a buffer is a gap with no row in it, so there is
nothing for another customer to claim there. What it changes is the arithmetic that decides how many
slots a service needs — and that arithmetic is the tenant's to set, below.

## Decided: whether the buffers count toward the service duration is a tenant setting

*(Author's own call, 2026-09-01, on the case that separates the two readings.)* A 70-minute service on
a 30-minute grid with a 10-minute buffer: two slots span 70 minutes end to end (30 + 10 + 30) but
carry only 60 minutes of slot time. So

- **counting the buffers** — capacity is `N*slot + (N-1)*buffer` — gives two slots, 12:00–13:10, and
  is the physically accurate reading for one continuous service: the worker does not stop working
  during a gap that exists only because the grid has one;
- **not counting them** — capacity is `N*slot` — gives three slots, 12:00–13:50, and never
  under-allocates, at the price of 40 minutes of that worker's day.

Neither is right for every trade, so `WorkerSchedule` gains a boolean the tenant sets. The
author's own framing — *перерывы включаются в групповой слот* — is the default: buffers count.

**The whole parameter lives in this item, not in `20-14`.** The field, its column, its console control
and its behaviour all arrive together, because the setting has no meaning at all while a service
longer than a slot is simply not offered (`20-14`'s interim rule). Putting the column in `20-14` would
have saved one small migration and cost the thing that matters more: a control in the schedule form
that changes nothing, which is worse than a missing one. `BookingCalendar.BufferMinutes` shipped that
way in `20-01` — "consumed by `20-02`; nothing reads it yet" — and it is not a precedent worth
repeating for something a tenant can see and toggle.

## Decided shape to weigh in implementation: a grouping column, leaning yes

Both candidates named, because this is the item's real data-model decision:

- **A `booking_id` column on `events`**, shared by the rows of one booking. Smallest migration, one
  table, the exclusion constraint untouched — but every read model that today returns one row per
  event must now group, and "one booking" becomes a convention the queries carry rather than a row
  that exists.
- **A real `bookings` table** with events pointing at it. Cleaner reads and a genuine aggregate for
  cancel/no-show to hang off — but a second aggregate, a bigger migration, and a second place for
  tenant isolation to be got wrong.

Leaning to the first, because a booking has no state of its own that the events do not already carry:
its status, its customer, its service and its deadline are the same on every row of the run. Confirm
or overturn when implementing, and record which.

## Scope

- The grouping mechanism above, plus its migration.
- `WorkerSchedule.BuffersCountTowardServiceDuration` (default true), its migration, and the console
  control on the schedule form — which shows the resulting arithmetic for that worker's own numbers
  ("услуга 70 мин займёт 2 слота, 12:00–13:10") rather than making the tenant work it out.
- Run-finding: from a chosen slot and service, the consecutive run that covers the service, or nothing.
- The multi-row claim, and the corresponding release on reject and cancel.
- `Cancel`, `Reject`, `MarkNoShow` and the confirmation sweep operate on the whole run.
- `20-04`'s pending-bookings queue shows **one row per booking**, not one per slot.
- `20-15`'s slot table shows every slot of a run as occupied, attributed to the same booking.
- The public booking surface offers a service whose duration needs several slots, and stops hiding it.
- Removal of `20-14`'s interim "a service longer than the slot is not offered" rule.

## Out of scope

- Per-service slot grids — a slot is still one row with one status, and a run is still made of whole
  slots.
- Runs spanning two business-local days. A run lives inside one day, which is also how a shop sells.
- Moving a booking to a different run — that is `20-17`'s subject if it ever needs one.

## Done when

- [ ] A 90-minute service on a 30-minute grid occupies three consecutive slots as one booking.
- [ ] The 70/30/10 case, both ways, as two tests with exactly those numbers: two slots ending 13:10
      with the setting on, three slots ending 13:50 with it off.
- [ ] Two customers racing for overlapping runs: exactly one wins, the loser's slots are all still
      `Available`, and no partial claim survives — proven in `Ago.Calendar.Concurrency.Tests`.
- [ ] A run whose middle slot is already taken is neither offered nor claimable when requested
      directly by id.
- [ ] Cancel, reject and no-show each release or mark every slot of the run, proven on a three-slot
      booking.
- [ ] The pending queue shows one row for a three-slot booking.
- [ ] `20-15`'s slot table shows all three slots occupied and attributed to the same booking.
- [ ] `20-14`'s "not offered" rule is gone, and a service longer than the slot is bookable.

## Open questions

- **What the setting is called on screen.** "Перерывы внутри длинной записи считаются рабочим
  временем" is accurate and unreadable; whatever replaces it has to be understood by a shop owner who
  has never thought about a slot grid, which is why the form shows the arithmetic for their own
  numbers next to the control. A naming question, not a structural one.
