# an operator sees their own numbers, and sees them first

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-17` — the same figures under the same rules, or this ships a second, laxer
  version of the tenant's report. `23-02` — a row an operator recognises as themselves.
- **Decision**: `docs/design/decisions.md` §7's rules apply; the need is `flows.md` 2.4

## Goal

An operator can look at the measures they are judged on, without their manager's permission and
before their manager mentions them.

Today every analytics surface is gated on `Permission.SiteConfigure` — the tenant-admin grant — so an
ordinary operator can reach none of them (`ui-inventory.md` §1's nav table, items 4 to 7).
`flows.md` 2.4 records the consequence exactly: *"a metric an operator first learns about from their
manager … is a metric they will manage rather than work to"*, and it destroys the data the tenant is
buying.

## Why the same numbers, computed the same way

`OperatorAnalyticsReadStore` already computes per-operator buckets — the console's **By operator**
table renders them today (`18-09`), and `23-17` widens them. What does not exist is a way for the
operator in that table to read their own row: `GetOperatorAnalyticsForSite` takes
`(RequestedBy, SiteId, From, To)` and gates on `site:configure`, with no operator-scoped query beside
it.

Computing the number a second way would be worse than not shipping it: the story's whole point is
that the operator and the tenant look at *the same* measure, and `flows.md` 2.4's own success test is
whether operators can predict their own numbers before seeing them.

## Context to read first

- `docs/design/flows.md` 2.4 in full, including the interest note — **tenant wins**, and what is owed
  back
- `docs/design/decisions.md` §7 — every rule applies here too, and the sample rule applies hardest,
  because one operator's slice of a small tenant's month is the smallest sample in the product
- `docs/design/ui-inventory.md` §1 (the gate table), §5.1, §5.2
- `docs/architecture/authorization.md` — `adr/0016`, and why a permission is not the same as a role
- `docs/backlog/23-17-*.md`

## Scope

- A query beside `GetOperatorAnalyticsForSite`, scoped to **the caller's own `OperatorId`**, taken
  from the validated principal and **never** from a parameter.
- **No new permission.** An operator reading their own row needs no grant, and a grant would be a
  thing a tenant could withhold — which is the failure this item exists to prevent. State that
  reasoning where the route is mapped, because "add a permission" is the reflex this codebase
  otherwise has.
- It reads the same store with the same window and the same rules, filtered — not a second
  computation. Assert that the operator's own figures equal their row in the tenant's report over the
  same range.
- The same treatment for the conversion figures (`GetConversionReportForSiteHandler`'s per-operator
  rows), because those are the ones a tenant actually discusses.
- **Only their own row.** An operator does not see a colleague's numbers; a leaderboard is
  `flows.md` 2.4's forbidden failure in one screen.
- **Where the shift is visible.** The measure must be fair to the shift they were given, so the
  screen shows the standard/additional split and the load buckets `23-17` computes — the two counts,
  never combined into a score.
- A console route an operator can reach, in the nav without `site:configure`.

## Out of scope

- Any ranking, comparison against colleagues, or target.
- A new metric. Everything here already exists as a number the tenant sees.
- Activity measures — forbidden by name in `flows.md` 2.4.
- Contact-reveal counts (`23-11`). They are a per-named-operator number that must not appear on a
  screen a person is judged on, and this is one — including when the person judging is themselves.

## Done when

- [ ] An operator with none of the gating permissions reaches the screen and sees their own figures.
- [ ] Those figures equal that operator's row in the tenant's own report for the same range —
      asserted, not eyeballed.
- [ ] The endpoint cannot return another operator's figures, including when an operator id is
      supplied in the request: a tenant-isolation test and a same-tenant-different-operator test.
- [ ] `23-16`'s rules hold on every rate this screen prints.
- [ ] The nav shows the entry to an operator holding no `site:configure`.

## Open questions

None.
