# 25-225 · Three console screens render a conversation's `state` with no default case

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-22, by the `25-221` worker while verifying that item's own third check (does
  anything read a conversation's `state` as a raw string in a way `ConversationState.Pending` — a
  brand-new state that value never held before — could silently break).

## What is actually true today, confirmed against real code

Three `ago-console` screens switch on a conversation's wire-level `state` string with **no default
case**, backed by a TypeScript literal union (`"Waiting" | "Assigned" | "Closed"`) that gives zero
runtime protection against a value the union doesn't list:

- `AdminConversationsPage.tsx` (lines 40-49) — fed by `GetAllConversationsForSiteHandler` →
  `ConversationReadStore.GetAllForSiteAsync`, which carries **no state filter at all**.
- `VisitorHistoryPanel.tsx` (lines 22-31) — fed by `GetVisitorHistoryHandler` →
  `GetVisitorHistoryAsync`, also unfiltered.
- `SearchConversationsPage.tsx` (lines 33-37) — fed by `ConversationSearchStore.SearchAsync`, also
  unfiltered.

Since `25-221`, a conversation can genuinely hold `"Pending"` as its `state` — a value none of these
three switches has ever had to handle, because nothing produced it before. None of the three crash on
it (`stateLabel` returns `undefined`, and `Badge`'s own `tone` prop defaults to `"neutral"` when its
lookup misses), but each renders a blank label with a default-toned badge instead of saying anything
true about the row.

`VisitorPanel.tsx` has an identical-looking switch and is **not** at risk — it is fed only through
`GetOperatorQueueHandler`, which already filters to `Waiting`/`Assigned` (unaffected by this item).
`ago-widget` has no exposure to conversation state strings at all (confirmed by a full-source grep).

## Scope

- Give each of the three switches a real case for `"Pending"` — matching whatever this codebase's own
  established convention shows for a conversation that exists but hasn't started (check `data-model.md`
  or how the console already labels/badges a comparable "not yet real" state elsewhere, rather than
  inventing new copy from scratch), **and** a `default` case so a future new state fails visibly (a
  console-side error boundary or a plainly-labeled "unknown state" fallback) instead of silently
  rendering blank again the next time this happens.
- Confirm whether a `Pending` conversation showing up in these three genuinely-unfiltered admin/search/
  history views is itself desired, or whether those queries should also exclude it the way the
  operator-queue read already does — read each handler's own purpose (admin overview, visitor history,
  search) and decide per-view rather than applying one blanket rule; state the reasoning either way.

## Out of scope

- `GetOperatorQueueHandler`/`VisitorPanel.tsx` — already correctly filtered, untouched.
- Any change to `ago-chat`'s own `ConversationState` enum or `25-221`'s own behavior.

## Done when

- [ ] All three switches handle `"Pending"` with real, considered copy, and have a `default` case for
      any future state.
- [ ] A decision is recorded (in the PR or this file) on whether each of the three views should
      continue to show `Pending` conversations or filter them out, with reasoning.
- [ ] `npm run typecheck`, `npm run lint`, `npm test`, and `npm run ux-gate` green.
