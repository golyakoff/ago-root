# 26-135 · [ago-android] Booking detail sheet — round-3 cosmetics to match the mockup

- **Stage**: 26 — third cosmetic pass on the confirmed-booking detail sheet (`26-117` built it, `26-125`
  fixed the first round). The mockup is the source of truth; the app must match it.
- **Status**: ready.
- **Found**: 2026-09-25 (author, side-by-side mockup vs app).

## Scope (`ConfirmedBookingsScreen.kt` detail sheet only)
Four differences the author flagged between the mockup (left) and the app (right):
1. **Field labels too small.** «Услуга» / «Мастер» / «Телефон» / «Подтверждён по SMS» / «Источник» render
   via `BookingDetailRow` at `labelMedium`; they must match the sheet's other primary text (the date line
   «Пятница 25 сентября», `bodyMedium`). `BookingDetailRow` is shared with `BookingsScreen.kt` — do not
   regress that screen (parametrise the label style, default unchanged).
2. **Values not emphasised / not aligned.** The values (service·duration, master, phone) must be **bold** and
   **right-aligned** to the sheet edge, as in the mockup. Applies to the «—» placeholder rows too.
3. **Missing dividers.** Thin horizontal lines between the field rows, as in the mockup.
4. **Buttons stacked.** «Перейти к диалогу» + «Закрыть» must sit in **one row** and definitely fit; shorten
   the primary label (new string resource, both languages) if the pair does not fit at ~360dp.

## Done when
- [ ] Detail-sheet labels match the date-line size; values bold + right-aligned; dividers between rows;
      both actions in one row that fits — verified against the mockup.
- [ ] `BookingsScreen.kt`'s own `BookingDetailRow` usage is not visually regressed.
- [ ] `ktlintCheck`, `lint`, `test`, `:app:compileDebugAndroidTestKotlin` green; no new literal strings.
