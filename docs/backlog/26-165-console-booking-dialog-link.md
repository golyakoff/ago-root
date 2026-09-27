# 26-165 · [console] Confirmed booking links to its originating dialog (adr/0184 C1w)

- **Stage**: 26. Design: `docs/design/26-112-bookings-names-contacts-navigation.md` (C1w / P3). Carried
  out of the refreshed 26-112 (26-112 shrank after ADR-0184: name collection already exists; the real
  remaining work is the dialog⇄booking link). Author-decided (Q-C): C1w now, C2 later.
- **Status**: done — console confirmed bookings now link to their originating dialog (ago-console#281,
  8a54bce), deployed to stand.

## One promise
The console confirmed-bookings page shows, on each chat-origin booking, a «Перейти к диалогу» link that
opens the conversation it was created in.

## Scope
- `src/api/calendarApi.ts`: add `originConversationId?: string` to the `ConfirmedBooking` type + mapping
  (the field is already on the wire; the console DTO drops it today).
- `src/pages/CalendarBookingsPage.tsx`: render «Перейти к диалогу» for a booking that has an
  `originConversationId`, linking to that conversation (reuse the console's existing conversation route);
  absent (no affordance) when there is none (Q-E parity — not a disabled state).
- i18n both languages; update the page test + fixture.

## Done when
- [x] Chat-origin confirmed bookings link to their dialog; non-chat bookings show no link;
      `npm run typecheck && lint && test && ux-gate` green. — ago-console#281 (bf97f75/8a54bce),
      all four gates green.
- [x] Deployed to the stand after merge. — ago-deploy 2709214 (console pin bump).
