# 26-39 · The «Мои»/«Ожидают» segmented control carries no counts

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23, reading the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) against `ago-android` `main` at `ad2859b`.

## Found

The mockup's segmented control carries a count inside each label:

```html
<div class="seg">
  <div class="on">Мои <span class="ct">3</span></div>
  <div>Ожидают <span class="ct">5</span></div>
</div>
```

with its own type rule for that number, distinct from the label beside it:

```css
.seg .ct{font-size:11.5px; font-weight:700; opacity:.85; font-variant-numeric:tabular-nums}
```

and its own container metrics:

```css
.seg{display:flex; margin:4px 16px 12px; border:1px solid var(--line-strong);
     border-radius:20px; overflow:hidden; height:38px}
```

The app draws the two labels and nothing else.

`26-30` is the item that deferred this, in its own Out of scope: "Channel/tag pills, the chip filter
row **and the tab counts** the mockup draws. No data behind any of them today; each needs its own item
when there is." That sentence is half right and half wrong, and this item exists because of the wrong
half: the channel/tag pills genuinely have no field behind them (Stage 14), but **the two counts are
already in the state object the screen renders from** — they are the lengths of the two lists it is
already holding. Nothing has to arrive from anywhere for this one.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/conversations/ConversationListScreen.kt:190-199` builds the
  control with a bare label and no count:

  ```kotlin
  SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
      ConversationListTab.entries.forEachIndexed { index, tab ->
          SegmentedButton(
              selected = state.selectedTab == tab,
              onClick = { onTabSelected(tab) },
              shape = SegmentedButtonDefaults.itemShape(index, ConversationListTab.entries.size),
              label = { Text(text = labelFor(tab)) },
          )
      }
  }
  ```

- `labelFor` (same file, `:270-275`) resolves exactly two strings —
  `R.string.conversation_list_tab_mine` («Мои») and `R.string.conversation_list_tab_waiting`
  («Ожидают») — and composes nothing onto them.
- The numbers are already in hand. `ConversationListUiState`
  (`conversations/ConversationListUiState.kt:57-72`) carries `mine: List<ConversationRowUi>` and
  `waiting: List<ConversationRowUi>`; this same composable already reads both, a few lines below, to
  decide which list to render (`:215-224`). `state.mine.size` / `state.waiting.size` are the counts,
  with no fetch, no field and no DTO change of any kind.
- The container metrics differ too: the code applies `.padding(16.dp)` on all four sides, where the
  mockup's `.seg` asks for `4px` above, `16px` either side and `12px` below, and a `38px` height. The
  Material 3 `SingleChoiceSegmentedButtonRow` supplies its own 40dp height and full-stadium shape,
  which is close enough to `height:38px; border-radius:20px` to leave alone; the asymmetric margin is
  not.

## Scope

One promise: **the segmented control is the mockup's segmented control** — each label carries its
tab's own count, and the row sits on the mockup's own margins.

1. Each `SegmentedButton`'s `label` renders «Мои» / «Ожидают» followed by that tab's count, the count
   set in the mockup's own `.ct` treatment — smaller than the label, bold, slightly dimmed, tabular
   figures — rather than as one undifferentiated string. `MaterialTheme.typography.labelMedium` is
   this app's 12sp token-backed role and the nearest the scale has to `11.5px`; lift the weight there
   rather than introducing an untraceable `11.5.sp` literal, the same rule `ConversationRowIdentityLine`
   already states for `.rname`'s own `14.5px`.
2. The counts come from `state.mine.size` and `state.waiting.size`. Nothing is computed in the view
   model, nothing is fetched, and no count is invented for a tab whose list has not loaded — before
   `state.hasData`, the labels render with no count at all rather than with a `0` that is really
   "unknown". A zero-length *loaded* list does render `0`; that is a real answer.
3. The row's padding becomes the mockup's asymmetric margin (`4dp` top, `16dp` horizontal, `12dp`
   bottom) instead of a uniform `16.dp`, named as constants with the CSS beside them the way this
   file's existing row metrics already are (`ConversationListScreen.kt:691-711`).

## Out of scope

- The filter chip row (`.chips` — «Оплата» / «Метки» / «Канал»). No tag or channel field exists on a
  conversation today; `26-30` deferred it for that reason and it stays deferred.
- The search icon the mockup draws beside `⋮` in this app bar. It opens a screen that does not exist
  (the mockup's own graph: `ConvList -- "лупа" --> Search`); an icon that opens nothing is the shape
  `26-15` already rejected for the visitor chip.
- The bottom bar's own unread badge — `26-46`.

## Done when

- [ ] «Мои» and «Ожидают» each show their own count, styled as the mockup's `.ct` rather than as part
      of the label text.
- [ ] The counts track a refresh, a claim and a live hub push without a restart — checked on a real
      device with at least one conversation moving between the two tabs.
- [ ] No count is drawn before the first answer arrives.
- [ ] The row's margins are the mockup's, and every metric in the change names the CSS rule it came
      from.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
