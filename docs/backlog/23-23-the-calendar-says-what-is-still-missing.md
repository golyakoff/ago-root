# the calendar says what is still missing before it can take a booking

- **Stage**: 23
- **Status**: done (2026-09-05), `ago-calendar#42`, `ago-console#108`. The six preconditions are
  derived from the booking path's own refusal points and computed as a funnel, so a tenant with
  one idle worker and one configured worker reads as ready — the real question is whether
  anybody bookable exists. `ux-gate` caught a defect the three usual commands could not: the
  readiness call sat in the same `Promise.all` as the workers list, so an outage of the
  independently deployed calendar service would have hidden a tenant's own workers. Fixed on
  both screens, including the one the gate never opens.
- **Depends on**: nothing
- **Decision**: none — the need is `docs/design/flows.md` 3.1

## Goal

A tenant setting the calendar up can tell, at any moment, whether a visitor could book right now —
and if not, which of the several things that must be true is not yet true.

`flows.md` 3.1 names the failure exactly: *"Must never happen: a setup that looks finished and
produces no slots."* That is easy to reach today because the preconditions are conjunctive and
invisible, and each of the four forms on `/calendar/setup` reports only its own success.

## The preconditions, which is why this is a read and not a hint

A calendar must exist and be published; a worker must exist, be active and be on that calendar; a
service must exist and be one the worker performs; working hours must exist for that worker on that
calendar; a schedule must be saved (`WorkerScheduleSection` already carries the note that a worker
materialises nothing until one is); and materialisation must have produced slots inside the horizon.
Six facts across five tables. A screen cannot infer them from the forms it just submitted, which is
why this is one server-side read rather than six pieces of client-side cleverness.

## Context to read first

- `docs/design/flows.md` 3.1, and 1.4 for the visitor's side of the same preconditions
- `docs/design/ui-inventory.md` §7.2 and §7.3 — what Setup and Workers show today, including the two
  substitute notes that are the only "what is missing" signals in the product ("Add a worker first"
  and "That worker is not on a calendar yet"), and that both `PageHead`s carry a title with no
  description
- `docs/design/briefs/calendar-operator.md`
- `docs/backlog/20-02-*`, `20-13-*`, `20-14-*`, `20-15-*` — template, horizon, materialisation
- `docs/adr/0084-*` (weekly or cycle) and `docs/adr/0085-*` (re-cutting)

## Scope

- One read in `ago-calendar` — a handler plus a Dapper read store over `calendars`, `workers`,
  `services`, `calendar_memberships`, the working-hours rules, the worker schedule and `slots` —
  answering: *can this tenant take a booking right now, and if not, which precondition is unmet.*
  A read store rather than a repository, the same `adr/0004` call `IContactsReadStore` and
  `IPendingBookingReadStore` already made: this returns rows shaped for a screen, never aggregates
  with invariants to enforce.
- The answer is a **list of named, ordered preconditions with a met/unmet state**, not a single
  boolean and not a sentence. The console must be able to render it any way it likes and a test must
  be able to assert which one is unmet; a prose string satisfies neither.
- **It never says "a slot exists" from configuration alone.** The last precondition is materialised
  slots inside the horizon, read from `slots` — the failure `flows.md` 3.1 names *is* a setup that
  looks finished, and configuration looking complete is exactly that appearance.
- Gated on `Permission.CalendarConfigure`, tenant-scoped like every sibling read, with the
  tenant-isolation test the others have.
- `ago-console`: the state appears where the setup happens — `/calendar/setup` and
  `/calendar/workers` — and each unmet precondition points at the form that fixes it.
- It survives the not-configured case: with `VITE_CALENDAR_API_BASE_URL` unset those screens are
  already an info alert (`ui-inventory.md` §7), and this must not turn that into an error.

## Out of scope

- Fixing anything the read finds. It reports; the existing forms remain the way to act.
- A guided wizard, a stepper, or any ordering of the setup screens. `flows.md`'s own closing rule:
  nothing there says how it should look, and neither does this.
- The chat side's equivalent (`23-06`/`23-07`). Same shape of need, different product, different
  preconditions, different data.
- Creating or deleting a calendar, editing working-hours rules, or the other add-only gaps
  `ui-inventory.md` §7.2 records. Real, and each its own item.

## Done when

- [x] A tenant with nothing set up gets every precondition unmet, in a stable order.
- [x] A tenant with a published calendar, an active worker on it, a service that worker performs,
      working hours and a saved schedule, but a horizon that has produced no slots, is reported
      **not bookable**, and the unmet precondition is the slots one.
- [x] A fully set-up tenant is reported bookable, **and a public booking against it succeeds in the
      same test** — the two must agree, or the read is decoration.
- [x] Another tenant's readiness cannot be read.
- [x] The console renders the state on both screens and links each unmet precondition to its form.

## Open questions

None.
