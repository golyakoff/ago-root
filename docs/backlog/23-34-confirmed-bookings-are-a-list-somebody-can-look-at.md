# confirmed bookings are a list somebody can look at

- **Stage**: 23
- **Status**: done
- **Depends on**: `23-31` reserves its place (Календарь → Записи)
- **Decision**: none needed

## Goal

A tenant can see what is actually booked, not only what is still waiting for them.

## What is actually true today, verified 2026-09-06

The calendar console has **five screens and none of them lists confirmed bookings**: the queue (which
`23-31` renames «В ожидании» because that is what it holds), setup, workers, availability, contacts.

So the answer to *"what is on for Thursday"* today is: open a customer card, or look at the widget as
a visitor would. Both are ways of asking the system a question it was never given a screen for.

## Why this is a gap rather than an oversight

`20-xx` built booking from the visitor's side and gave the operator the one screen that needed an
**action** — the queue. A list of things requiring no action is easy to skip when the work is scoped
from "what must somebody do next", and it stays invisible afterwards for the same reason: nobody hits
an error, they just quietly do without.

## Scope

- Confirmed bookings for the tenant, readable by day and by master, with the customer and the service.
- **It is a read, and it stays one.** Cancelling or moving a booking is a different promise with its
  own notification consequences for the customer.
- It obeys the account's contact-visibility rung the way every other calendar read does (`adr/0123`) —
  a masked phone here must be masked for the same reason it is masked in Клиенты.

## Out of scope

- Editing, cancelling, rescheduling.
- A calendar grid. A list ordered by time answers the question; a grid is a second design conversation.

## Done when

- [x] A tenant can see confirmed bookings by day, with master, service and customer.
      `ago-calendar` `e3057db` (PR #48), `ago-console` `d94ca4d` (PR #151). `ConfirmedBookingReadStore` groups by booking and orders `local_date, worker, starts_at`; the screen renders day→worker with counts at each level rather than one flat table, which is the "how full is a day" question this item was actually about.
- [~] A masked phone is masked here too, and revealing it writes the same record.
      **Masked correctly; no reveal exists to write a record for.** The screen renders the phone exactly as the server returns it, proven by `ACallerHoldingCustomerRead_SeesTheMaskedPhone_WhenTheTenantsRungCallsForIt`. There is no reveal control here — and none on the sibling «Клиенты» screen either, so this is consistent rather than an omission. `23-30` owns reveal, and **its scope names four screens and not this one**, because this screen did not exist when it was written. See `23-91`.
- [x] Another tenant's bookings are unreachable, asserted the way the other calendar reads are.
      `ConfirmedBookingsTests.TheReadStore_IsTenantIsolated`, against real Postgres, asserted the way the other calendar reads are.
