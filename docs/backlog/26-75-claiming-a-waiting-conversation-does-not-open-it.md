# 26-75 · Claiming a waiting conversation does not open it

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, by the author, live on a real device: claimed a waiting visitor from
  «Ожидают», and the row simply disappeared from view — no navigation into «Мои» or the thread, no
  visible confirmation the claim did anything beyond an empty list.

## Found

The author's own words: "я забрал человека из ожидания, он просто пропал из списка. Было бы удобнее
переключиться в Мои и открыть его для диалога - это очевидный 100% следующий шаг для этой активности."

`WaitingRow`'s own doc comment (`ConversationListScreen.kt:672-679`) already made this a deliberate
choice, not an oversight — but it cites the wrong precedent:

> **No confirmation dialog, and no navigation on claim** — `ago-console`'s `ClaimConversationButton`'s
> own doc comment: taking a conversation is the ordinary, reversible act this whole item exists to
> make reachable.

`ClaimConversationButton` (`ago-console/src/pages/ClaimConversationButton.tsx`) is real, and its own
"no navigation" reasoning is real — but it is only ever used from `AdminConversationsPage` and
`SearchConversationsPage`, two monitoring/search screens where an admin plausibly claims several rows
in a row while scanning a table. **It is not used anywhere in the operator's own primary workspace.**

The console's actual primary-workspace equivalent of Android's «Ожидают» tab is
`WorkspaceLayout`/`ConversationList.tsx`, and it already decided the opposite, in `23-04`:

> **`23-04`: a waiting row is a real link now, the same shape as an assigned one.**
> `OperatorHub.JoinConversationAsync` already claims a still-`Waiting` conversation for whoever joins
> it... the row is a `NavLink` to the same `/conversations/{id}` route the assigned rows already use,
> and clicking it is a deliberate take (`ConversationAssignmentSource.Taken`), not an accident.

So on the console, claiming from the screen an operator actually works a shift in **does** navigate
straight to the thread — that is exactly the behaviour the author is asking Android to match, and it
already exists as a decided, shipped precedent one file away from the one Android actually cited.

## What is actually true today, confirmed against real code

- `ConversationListViewModel.claim()` (`conversations/ConversationListViewModel.kt:195-221`): on
  `ClaimResult.Claimed`, calls `refresh()` and nothing else. No tab switch, no navigation event of any
  kind is emitted.
- `ConversationListScreen.kt`'s `WaitingRow` keeps its own explicit **Claim** button per row
  (`onClick = onClaim`, line 689) — unlike the console's whole-row `NavLink`, tapping the row itself
  does nothing; only the button claims. That shape is not in question here and does not need to
  change — see Scope below.
- `docs/navigation.md`'s own "A new assignment arriving never navigates" rule (§ line 366) is about a
  *different* event: a `ConversationAssigned` push arriving while the operator is mid-conversation with
  someone else, which must not teleport them away (`ago-console`'s `WorkspaceLayout.tsx` doc comment,
  ported deliberately). **It says nothing about a deliberate, operator-initiated claim** — the two are
  not the same event, and this item does not touch that rule.

## Scope

One promise: **claiming a waiting conversation takes the operator straight into it**, matching the
console's own primary-workspace behaviour.

1. On `ClaimResult.Claimed`, in addition to `refresh()`, switch `selectedTab` to
   `ConversationListTab.Mine` and navigate to the thread for that `conversationId` — the same
   destination `onRowOpened` already sends an operator to when they tap a row in «Мои».
2. Keep the existing explicit **Claim** button as the trigger — do not turn the whole waiting row into
   a tap-to-claim target the way the console's `NavLink` does. The console's row-as-link shape exists
   because a mis-click there costs nothing more than one more conversation in the operator's own list
   (`ClaimConversationButton`'s own doc comment, quoted above) — Android already made the same
   judgement by giving the row a dedicated button rather than a bare click target, and this item is
   about what happens *after* a claim succeeds, not about relitigating that.
3. `ClaimResult.Refused` keeps its current behaviour exactly — inline error, row stays in «Ожидают»,
   no navigation, no retry. Losing a claim race is not a reason to move the operator anywhere.
4. State whether the switch is instant or waits for `refresh()`'s own re-fetch to confirm the row
   actually moved — the console's `onClaimed` fires "directly from the successful response... there is
   no completion poll to wait on first" (`ClaimConversationButtonProps.onClaimed`'s own doc comment),
   which is the same synchronous guarantee Android's `ClaimResult.Claimed` already carries.

## Out of scope

- Automatic assignment (`onAssigned`, a hub push). `docs/navigation.md`'s existing rule stays exactly
  as it is.
- Any change to `ClaimResult`/`QueueResult` or the server-side claim call.
- The console's own Admin/Search claim buttons — already correct for their own screens.

## Done when

- [ ] Claiming a waiting conversation on a real device switches to «Мои» and opens the thread, with no
      extra tap.
- [ ] A refused claim (lost race) still shows its inline error and stays in «Ожидают» — confirmed no
      regression via the existing claim-refusal test coverage.
- [ ] A new assignment arriving via hub push while the operator is elsewhere still does not navigate —
      confirmed no regression via the existing "never navigates" test.
- [ ] `./gradlew ktlintCheck lint test assembleDebug assembleDebugAndroidTest` green.
