# 26-284 · Клиенты detail-page layout iteration 2 (segment order, spacing, action-button row, single-visit, badge placement, cancel-via-card)

- **Stage**: 26. Kind: implementation (Android + mockup). Author's second polish pass on the client-detail
  hub, from live testing 2026-09-29 (screens 1-4). Sibling of 26-282 (list) and 26-283 («Записать»),
  delivered together in one clients-iteration-2 pass.
- **Status**: done 2026-09-29 — merged as ago-android#211 (detail layout: segments swapped, header raised, tighter bottom padding, badges under the phone, action-button row, «Единственный визит», cancel via the booking card) + ago-android-design#22 (mockup segment swap).
- **Repos touched**: `ago-android` (ClientDetailScreen), `ago-android-design` (mockup `clients.html` — the
  segment-order swap must land there too).

## Author's items (verbatim intent, screens 3/4 as the target)

1. **Swap the segments**: Прошедшие on the LEFT, Предстоящие on the RIGHT (currently Предстоящие left).
   Apply the same swap to the mockup `https://android-design.agochat.ru/clients.html`.
2. **Top spacing**: too much empty space — X-close, then a huge gap, then the name. Raise the name/header
   up to the level of the X-close button.
3. **Bottom padding**: too much padding at the bottom — tighten it.
4. **Action buttons** (screens 3/4): «Позвонить» moves from the right of the phone number to a button
   ROW below. Layout: if the client HAS a dialog → row1 `[Позвонить] [Диалог]`, row2 `[+ Записать]`
   (full width). If NO dialog → one row `[Позвонить] [+ Записать]` (no Диалог button).
5. **«+ Записать»** (26-283): new button; tapping opens the manual-booking flow with the client already
   selected (reuse `PersonId`, skip phone/recognition — land on service selection).
6. **Single visit**: when first visit == last visit, show one row «Единственный визит» instead of two.
7. **Badges under the phone**: the pills («Постоянный клиент»/«N записей», and «N неявок» when present)
   sit directly under the phone number (screens 3/4), above the warning banner and the action buttons.
8. **Remove the inline «Отменить»** from the booking row (added in 26-275) — cancelling is now reached by
   opening the booking card (26-279 B8), which offers «Отменить» there.

(No-show badge on the list itself is a data matter, not a code gap — author confirmed.)

## The one promise

The client-detail hub matches screens 3/4: compact top/bottom spacing, past/upcoming segments in the new
order (mockup included), a call/dialog/record button row, «+ Записать» into a pre-bound booking, a
single-visit label when applicable, badges under the phone, and cancel reached through the booking card.

## Done-when

- [ ] Segments swapped (Прошедшие left / Предстоящие right) in the app AND the mockup `clients.html`.
- [ ] Header name raised to the X-close level; bottom padding tightened.
- [ ] Action-button row per screens 3/4 (dialog present → two rows; absent → one row with Записать).
- [ ] «+ Записать» opens manual booking pre-bound to the client (26-283).
- [ ] «Единственный визит» when first == last visit.
- [ ] Badges directly under the phone.
- [ ] Inline row «Отменить» removed; cancel via the booking card.
- [ ] Strings both languages; ktlint/testDebugUnitTest/assembleDebug/compileDebugAndroidTestKotlin green.
