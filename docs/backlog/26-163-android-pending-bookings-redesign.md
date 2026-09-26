# 26-163 · [android] Redesign «Записи → Ожидают» to the Confirmed detail-card style + fix action logic

- **Stage**: 26 — Android app. Pattern to mirror: the shipped «Утверждены» (Confirmed) view —
  `ConfirmedBookingsScreen.kt` (`ConfirmedBookingRow` + `ConfirmedBookingDetailSheet`/`Body`, 26-117).
- **Status**: ready — author-requested 2026-09-26 from a live screenshot.

## Why
The «Ожидают» (Pending) tab is a raw engineering view: it renders bare hex ids (`Услуга 01a08a02`,
`Мастер 01a084ec`, `Календарь 01a084eb`) instead of names, and offers **«Не пришёл» (no-show) on a
pending booking — which is logically impossible** (a no-show only applies to a *confirmed* booking the
client didn't attend). The Confirmed tab, by contrast, shows real service/master names and a polished
row-tap detail card.

## One promise
The Pending tab shows bookings with real names (service, master, person) and a polished detail card in
the same visual language as the Confirmed tab, and offers only the actions valid for a *pending* booking.

## Scope
- Mirror the Confirmed treatment: a clean row (names, not hex; fall back to "—"/masked like Confirmed,
  never the raw GUID) and a row-tap `ModalBottomSheet` detail card matching `ConfirmedBookingDetailBody`
  (date/time, service, master, duration, person via display-merge, «Из чата» when chat-origin).
- **Fix the action set**: remove «Не пришёл» from pending (no-show is confirmed-only). The valid
  pending actions are the approve/reject/cancel transitions the calendar backend actually exposes for a
  pending booking — confirm which apply and show exactly those (the header «Всё подтверждается
  автоматически» implies auto-confirm; reconcile the shown actions with the real state machine).
- **Names source**: check whether `PendingBooking` (read model + wire DTO) already carries
  service/worker names the way `ConfirmedBooking` does. If it only carries ids, add the names to the
  calendar read-model projection + DTO (a join, no migration expected) and the Android client — the same
  shape `ConfirmedBooking` uses. Person name via the chat Person display-merge (26-162 pattern).
- Strings as resources both languages; no literals.

## Done when
- [ ] Pending tab renders names (no hex) + a detail card matching the Confirmed style; only
      logically-valid pending actions shown (no «Не пришёл»); gating unchanged.
- [ ] Verified: `ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green (+ calendar suite if
      the read model is touched); strings both languages.
