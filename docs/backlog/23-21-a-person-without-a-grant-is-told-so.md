# a person without a grant is told so, instead of seeing nothing

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: none — the need is `docs/design/flows.md` 4.3 and its *absent and forbidden look
  identical* rule

## Goal

An operator who lacks a grant sees that the capability exists and that they do not hold it, instead
of an interface in which it was never there.

Today the console draws a navigation item when `hasPermission(...)` is true and draws nothing when it
is false (`consoleNav.ts`'s gate column, `ui-inventory.md` §1), so **not entitled** and **does not
exist for this tenant** render identically. That is how `22-14` was found, and `flows.md` 4.3 names
it as its own must-never-happen: *"a person granted access who sees nothing and cannot tell why …
every gated surface must say what a person who is not entitled sees. 'Nothing' is a decision, and
usually the wrong one."*

After this, `GET /api/v1/operators/me` tells the console two separate facts — what this tenant has,
and what this caller holds — and the console renders the difference.

## Context to read first

- `docs/design/flows.md` 4.3 and *What makes this interface hard* → "Absent and forbidden look
  identical"
- `docs/design/ui-inventory.md` §1 (the nav table and its gates), §13.15 (one environment flag hiding
  a whole screen's content, which is a *third* reason a screen can be missing), and the
  permission-denied idiom repeated by hand across the screens
- `docs/design/design-system/states.html` — the state vocabulary that exists today
- `docs/architecture/authorization.md` — `adr/0016`'s RBAC and its `22-14` section
- `docs/adr/0093-*` — one role catalogue across both products
- `docs/backlog/22-14-*` and `docs/backlog/12-04-*`
- `Ago.Chat.Api/Operators/OperatorsEndpoints.cs`;
  `Ago.Chat.Application/UseCases/ListEnabledModulesForSite/*` (`23-01`) — the site-scoped module
  read whose answer the tenant half of this response overlaps with

## Scope

- `GET /api/v1/operators/me` returns two lists: the permissions the caller holds, as today, **and**
  what this tenant has switched on — the site's enabled modules and the capabilities its tier
  includes. **Two facts, never one merged list**, because merging them is the bug.
- Reading the tenant's half must not become a second uncontrolled cross-tenant read. It is scoped to
  the caller's own site claim — the exact failure `23-01` closed on the neighbouring route — and
  `tenant-isolation.md` gains the row.
- `ago-console`: `consoleNav.ts` and the page-level refusals distinguish three cases —
  **the tenant does not have this** (say so, and where it comes from), **the tenant has it and you do
  not** (say so, and who can grant it), and **this deployment is not configured for it**
  (`ui-inventory.md` §13.15's existing info-alert case, which is already correct and must not be
  swept into the other two).
- One shared treatment, not the current per-screen copy: a `PageHead` with no description, a danger
  alert and a "Back to queue" link is repeated by hand on every gated page today, and the *forbidden*
  case now needs a different, non-alarming shape from the *absent* one.
- `design-system/states.html` gains the missing state, so the design pass has a name for it.

## Out of scope

- Changing who holds which permission. This item makes the current answer legible; `23-22` is the
  screen that changes it.
- Job-shaped role names. `flows.md` 4.3 wants a tenant to think in jobs and have the system translate
  to permissions; that needs a role catalogue nobody has designed. See the stage report.
- The `/owner` screens. `ui-inventory.md` §8.1 records their refusal state as already correct and
  their English as deliberate.

## Done when

- [ ] An operator lacking `calendar:configure` on a tenant that **has** the calendar sees the entry
      and is told they do not hold it.
- [ ] An operator on a tenant that does **not** have the calendar sees a different thing, and the two
      are distinguishable in a test asserting the rendered state rather than the pixels.
- [ ] A deployment with `VITE_CALENDAR_API_BASE_URL` unset still shows the existing third state.
- [ ] `GET /api/v1/operators/me` cannot report another tenant's enabled modules — a tenant-isolation
      test.
- [ ] A failure of that call is still distinguishable from an empty answer (`ui-inventory.md` §13.11
      records that it currently is not; this item must not make that worse, and says whether it fixes
      it).
- [ ] `authorization.md` and `tenant-isolation.md` carry the widened response;
      `design-system/states.html` carries the new state.

## Open questions

None.
