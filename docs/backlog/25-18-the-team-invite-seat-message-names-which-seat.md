# 25-18 · The team-invite seat message names which seat it is spending

- **Stage**: 25
- **Status**: done, narrower than filed — `ago-console#183`; the role-naming half shipped, the
  per-role limit did not, because it does not exist server-side yet. See Done-when and `25-25` below.
- **Depends on**: `ago-business` decision `0011` ("администраторы считаются отдельно от мест") is
  the decision; it turned out **not yet built** where this item assumed it was — see below.
- **Found**: 2026-09-09, the author adding an operator

## What is actually true

`OperatorsTeamPage.tsx`'s invite flow shows *"Это займёт ещё одно место — на сайте станет 2/2"*
(`operatorsTeamInviteCostBody`, `ago-console/src/i18n/ru.ts`) regardless of which role is being
invited. Since `ago-business`'s own decision `0011`, Operator and Administrator seats are counted
**separately, each against its own limit** — the message describes a single shared pool that no longer
exists.

Inviting an Administrator does not touch the Operator count, and the message should say so: how many
of how many Administrators there will be. Inviting an Operator is the mirror case.

## Scope

- The invite screen already knows which role is being invited (it is what the author picks before this
  message is shown). Make the message read the count and limit **for that role specifically** —
  *"...место Администратора — станет 1/1"* or *"...место Оператора — станет 2/2"* — and update live as
  the role selector changes, not fixed at the values the page loaded with.
- Whatever already computes "занято/лимит" for the summary line elsewhere on this page (or a sibling
  page) is very likely the source to reuse per-role here rather than a second computation — check before
  writing a new one.

## Where this is likely to go wrong

- **The two limits are not necessarily the same number.** Free-tier Solo's own grid (`ago-business
  0012`) gives two Operator seats and Administrators "beyond them" — do not assume the two counts share
  a ceiling.
- **This is one string, but it needs the count for a role the author has not committed to yet** — the
  message must react to the in-progress selection, not the page's initial load state.

## What this item's own premise got wrong, found while building it

This item assumed decision `0011` was already live server-side and only needed surfacing in copy.
Checked directly in `ago-chat` (`Site.SeatLimit`, `GetSeatAssignmentSummaryHandler`,
`ToggleOperatorSeatHandler`, `IOperatorRepository.CountHeldSeatsAsync`): there is exactly **one**
`SeatLimit` on `Site`, and every role is gated against it identically. No `AdminLimit` field, no
per-role query, anywhere. `ago-business 0011` itself says this plainly — *"Тариф с двумя
администраторами нельзя продавать, пока второго нечем назначить"* — and names `23-71`/`23-72`/`23-67`
as its own prerequisites; none of them built a second limit. `23-71` only let an account's
administrator sign in without holding a seat, which is a different thing.

## Done when

- [x] The invite message names the role ("место Оператора" / "место Администратора") rather than
      speaking of "a seat" abstractly.
- [ ] **Not done, honestly**: the count and limit shown are that role's own. No separate Administrator
      limit exists to show — the message still shows the one combined figure the server actually
      enforces, stated as a deliberate limitation in code rather than a fabricated number. `25-25`
      files the missing backend half.
- [x] A test exercises both roles and asserts the message text differs between them.
