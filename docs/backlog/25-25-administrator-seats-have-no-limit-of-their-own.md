# 25-25 · Administrator seats have no limit of their own

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business` decision `0011` is the decision this item finishes implementing.
  `23-71`/`23-72`/`23-67` are the prerequisites `0011` itself names — check each is actually done
  before assuming this item can proceed cleanly on top of them.
- **Found**: 2026-09-09, while building `25-18`'s per-role seat message

## What is actually true

`ago-business` decision `0011` ("администраторы считаются отдельно от мест") says Operator and
Administrator seats should be counted against two separate limits. Checked directly in `ago-chat`
while building `25-18`: `Site` carries exactly **one** `SeatLimit`, and every seat-holding role —
Operator or Administrator — is gated against it identically (`GetSeatAssignmentSummaryHandler`,
`ToggleOperatorSeatHandler`, `IOperatorRepository.CountHeldSeatsAsync`). No `AdminLimit` field exists.
No per-role count exists. The decision was made; the mechanism it describes was never built.

`25-18` shipped the console side that names which role an invite spends (`ago-console#183`) but
deliberately left the count/limit shown as the one combined figure the server actually enforces,
rather than inventing a second number nothing backs.

## Scope

- `Site` (or wherever seat capacity is actually tracked) gets a second, independent limit for
  Administrator seats, alongside the existing `SeatLimit` for Operators.
- Whatever currently counts held Operator seats (`IOperatorRepository.CountHeldSeatsAsync` or its
  equivalent) gets an Administrator-scoped counterpart, or is generalized to take a role.
- The two limits are genuinely independent: granting or revoking an Administrator seat must not move
  the Operator count, and vice versa.
- Once this lands, `25-18`'s own remaining Done-when box — the invite message showing that role's own
  count/limit rather than the combined figure — becomes buildable; this item does not itself need to
  touch the console.

## Where this is likely to go wrong

- **Check the three prerequisites `0011` itself names before assuming they are done.** `23-71` let an
  administrator sign in without holding a seat — that is not the same as giving Administrators their
  own counted pool, and it is easy to mistake "an administrator doesn't need a seat to log in" for "an
  administrator's seat is limited separately." Read `23-71`/`23-72`/`23-67` and confirm what each
  actually shipped before writing the new limit on top of an assumption.
- **What is the actual number?** `ago-business 0012` is the source for what the Administrator limit
  should be per tier (Solo, Business) — do not invent a figure; read the grid.

## Done when

- [ ] A site's Administrator seat count is gated against its own limit, independent of the Operator
      limit, proven by a test that grants/revokes each role and confirms the other's count is
      unaffected.
- [ ] The limit values match `ago-business 0012`'s own grid per tier.
- [ ] `25-18`'s invite message can now show the correct per-role count/limit — either finished in this
      same change or explicitly handed back to a console-side follow-up, stated either way.
