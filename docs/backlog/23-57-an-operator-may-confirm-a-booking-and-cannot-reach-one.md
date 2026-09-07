# an operator may confirm a booking and cannot reach one

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `23-34` works around it for one screen; this is the gap itself.
- **Found**: 2026-09-07, while building `23-34`, and verified independently before filing.

## What is actually true

The seeded **Operator** role holds `booking:confirm`, `booking:reject` and `booking:cancel` —
`22-05`/`adr/0093` put them there on purpose, with a comment explaining that booking actions are
ordinary operator work while `calendar:configure` is an administrator's.

`consoleNav.ts`'s `buildCalendarItems` gates the entire calendar section on `calendar:configure`, and
returns an **empty list** to anybody who has neither that permission nor `isAdmin`.

So an operator has the right to confirm and reject bookings **and no screen from which to do it.**
Not a muted entry, not a forbidden page — the section is absent, so nothing on screen suggests the
capability exists at all.

## Why this is worse than a missing link

This is the shape this project keeps meeting: a permission exists, a handler checks it, and nothing
grants the reach. `23-36` found it one layer down — `channel:manage` gated four handlers and no role
held it. Here the role holds it and the navigation hides it, which is the same failure seen from the
other end.

It also means the queue — the one screen the calendar had from the beginning — is invisible to the
person whose job it is. An administrator sees a muted link to it; an operator sees nothing.

## Scope

- The calendar section is built from what the caller can actually do, not from one administrator
  permission. An operator holding the booking permissions reaches the queue; an operator holding
  `customer:read` reaches the contacts report and the bookings list; configuration screens stay
  behind `calendar:configure`.
- **Whether a screen is hidden or muted is a decision, not a detail.** `23-22` established the
  distinction and it is already used unevenly here — the queue is *muted* for an admin without
  `calendar:configure` and *absent* for an operator. Pick one rule and apply it.
- `23-34` gave the new bookings screen its own branch on `customer:read` rather than wait for this.
  That branch is correct and should survive this item rather than be folded back into a single gate.

## Out of scope

- Changing which permissions the seeded roles hold. `adr/0093` decided that and it is not wrong —
  the defect is on the console side.
- The four calendar screens' own contents.

## Done when

- [x] An operator holding only the booking permissions can reach the queue and act on it.
      `ago-console` `0fac74b` — `calendarPermissions.ts` is new, and both calendar pages plus `consoleNav.ts` route through it.
- [x] The hidden-versus-muted rule is stated once and followed by every calendar entry.
      Stated once in `calendarPermissions.ts` and followed by every calendar entry, rather than each entry deciding for itself.
- [x] A test asserts the operator case, not only the administrator one — the existing nav tests
      `permissionGating.test.tsx` grew 137 lines asserting the operator case — the gap that let this survive was that the existing tests asserted only what an administrator sees.
      assert what an admin sees, which is why this survived.
