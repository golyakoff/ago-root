# 26-16 · The bottom navigation and the back-button contract

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21. `navigation.md` §"What the back button does" opens with the reason this is a
  real item rather than a detail of some other one: "Android's system back is a real contract and the
  console has no equivalent of it, so it is stated once here." Six clauses, none of which any screen
  item would own.
- **Verified**: 2026-09-21 — the hide-when-empty rule is the console's own and is documented in
  `ago-console/src/shell/consoleNav.ts:57-67`: `buildSection` returns `null` rather than an empty
  section and the caller filters those out, which is what makes an ordinary operator's rail four
  sections rather than seven collapsed ones. That file also carries `permissionsKnown` as a distinct
  state from "has no permission" — worth porting, since drawing a four-item bar because permissions
  have not loaded yet is a different bug from drawing one because the operator lacks the grant.
- **Depends on**: `26-14` (a real destination to navigate to), `26-12` (the session the permission set
  comes from).

## What this item is

The app's shell: five destinations, drawn according to what this operator actually holds, and a back
button that behaves the way `navigation.md` specifies. One promise: **the app navigates correctly.**

## Scope

- **Five destinations in `navigation.md`'s own order — Диалоги, Записи, Команда, Аналитика, Ещё** —
  ordered by how often a shift touches each, not by the console rail's order. An earlier draft had
  Команда and Аналитика the other way round and the author corrected it; the corrected order is what
  every mockup frame and `architecture.md` now state.
- **A destination with nothing inside it is not drawn.** The identical rule `buildSection` applies: an
  ordinary operator with no calendar grant sees **four** destinations, not five greyed ones; an
  administrator sees five. The floor is four, because Команда, Аналитика and Ещё each always carry at
  least one item, so the bar never degrades into something Material has no shape for.
- **The permission vocabulary in `:core:domain`** — arriving now because this is its first consumer,
  which is the same rule `0-01` applied to the platform's ports — and the operator's own permission
  set read once per session, with **"not loaded yet" distinguished from "not held"**.
- **Every gate is the same gate the console applies, for the same stated reason**: hiding a control is
  UX, and the server's own `IPermissionChecker` is what actually refuses (`authorization.md`,
  `scope-inventory.md`'s own gate column). The app invents no permission of its own.
- **Ещё as a list-of-lists** — the three folded sections as headers, their items as rows, no nesting
  beyond that. Rows exist only for screens that exist; a row pointing at nothing is the same
  hide-when-absent rule, not a placeholder to fill in later.
- **The back-button contract, all six clauses** (`navigation.md`):
  - back from a thread returns to the list, keeping scroll position and filters;
  - back from any Ещё screen returns to the Ещё list, not to the previous bottom-bar destination;
  - back on a bottom-bar destination other than Диалоги returns to Диалоги; back on Диалоги exits;
  - back inside a multi-step flow returns to the previous step (the re-cut is the case this was
    written for; it is not in this wave, but the rule is implemented here);
  - sheets, filter sheets and confirmation dialogs are dismissed by back before the screen under them;
  - **back never discards a composer draft silently.**

## Out of scope

- **The tablet navigation rail and `ListDetailPaneScaffold`** — `plan.md`: phone first, tablet last,
  and no phase is gated on it.
- Any Записи, Команда or Аналитика screen. The destinations exist and are empty-but-honest; their
  contents are later waves.
- Deep links. The two push ones arrive with `26-18`; App Links for invites and policies are their own
  later item.
- The Settings screen itself (`26-17`) — this item puts the row in Ещё.

## Done when

- [ ] An operator without a calendar grant sees four destinations; one with it sees five — both
      against real identities on a real phone, not fixtures.
- [ ] Permissions still loading does not render a wrong bar that then changes under the operator —
      say what it renders instead.
- [ ] **Every clause of the back contract has a Compose UI test**, written here and run in CI by
      `26-20`.
- [ ] Rotating the device and returning from the background preserves the selected destination and
      each destination's own back stack.
- [ ] `./gradlew ktlintCheck lint test` green; counts reported.
