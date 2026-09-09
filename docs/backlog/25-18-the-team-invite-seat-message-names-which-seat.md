# 25-18 · The team-invite seat message names which seat it is spending

- **Stage**: 25
- **Status**: ready
- **Depends on**: `ago-business` decision `0011` ("администраторы считаются отдельно от мест") is
  already the live rule this item's copy has to match
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

## Done when

- [ ] The invite message names the role ("места Оператора" / "места Администратора") rather than
      speaking of "a seat" abstractly.
- [ ] The count and limit shown are that role's own, and update when the role selector changes.
- [ ] A test exercises both roles and asserts the message text differs between them.
