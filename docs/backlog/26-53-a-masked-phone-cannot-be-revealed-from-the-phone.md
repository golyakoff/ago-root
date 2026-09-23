# 26-53 · A masked phone cannot be revealed from the phone

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-52` (Клиенты — the first screen in the app with a masked phone on it)
- **Found**: 2026-09-23, reading `ago-console/src/calendar/calendarFormat.tsx` and
  `ago-console/src/api/calendarApi.ts` against the approved mockup Artifact ("AGO Chat для Android",
  `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`), whose §04 draws `Показать` on both the pending card and the
  contact row and captions it «под аудитом».

## Found

Every screen in the mockup that shows a customer's phone shows it masked, with a quiet `Показать`
beside it, and the mockup's own navigation graph draws the loop explicitly —
`Contacts -- "Показать · под аудитом" --> Contacts`, and the same on `BookingCard`. The audit is the
point: the product records who revealed which number, and there is a whole console screen for reading
that record back (`/calendar/phone-reveals`).

Once `26-52` lands, this app is the one client that shows a masked number and offers no way to see it
— which on a phone is worse than on a desktop, because "call this customer" is the single most natural
thing to want to do next on a device that is a telephone.

## What is actually true today, confirmed against real code

- The call is one function, already shared by three console screens:
  `ago-console/src/api/calendarApi.ts:701` —
  `revealCustomerPhone(token, customerId, surface): Promise<{ phone: string }>`. The third argument is
  the **surface name**, recorded in the audit trail: `CalendarQueuePage.tsx:200` passes
  `"ConsoleQueue"`. An Android caller therefore needs its own surface strings, not a borrowed console
  one — otherwise the audit trail cannot tell a phone reveal from a desktop one, which is exactly the
  question that trail exists to answer.
- The control is drawn from the server's own flag, never guessed:
  `ago-console/src/calendar/calendarFormat.tsx`'s `renderPhone`, reached from
  `CalendarContactsPage.tsx:160` and `CalendarQueuePage.tsx:238`. `PendingBooking.masked`'s own
  comment (`calendarApi.ts:197-201`) states the rule: "renders a Reveal control exactly when this is
  `true`, never inferring it from the string's own shape."
- The response replaces the number **for every row belonging to that customer**, in place —
  `CalendarQueuePage.tsx:201`, `CalendarContactsPage.tsx:126`. A customer with three pending bookings
  is revealed once, not three times.
- One reveal at a time is tracked by customer id, not row id (`CalendarQueuePage.tsx:69`,
  `revealingCustomerId`) — same reason.
- Android has none of this: there is no masked value anywhere in the app today.

## Scope

One promise: **an operator who holds the grant can reveal a masked customer phone, and the reveal is
recorded as having happened on Android.**

1. `revealCustomerPhone` on the `BookingsApi` port `26-48` introduces, taking the customer id and a
   **surface** string.
2. **New surface names, one per screen that can reveal** — `"AndroidContacts"` and, when `26-49`'s
   card gains one, `"AndroidQueue"`. Named as constants in one place, never inline, and stated in the
   report so whoever reads the audit trail knows what they mean. Reusing `"ConsoleQueue"` would
   silently corrupt the one record that distinguishes the clients.
3. The control is drawn exactly when the server says `masked` is true, and never from the string's
   shape.
4. A successful reveal replaces the number on every row for that customer currently on screen, and
   one reveal is in flight per customer at a time.
5. A refusal renders the server's own message and leaves the masked value in place — a reveal an
   operator is not entitled to must not look like a network hiccup.

## Out of scope

- **Dialling the number.** An `ACTION_DIAL` intent is the obvious next thing and is genuinely a
  separate promise (and a separate permission conversation). File it when somebody wants it; do not
  fold it in here, where it would make a reveal and a phone call one tap apart by accident.
- **Reading the audit trail on Android.** `/calendar/phone-reveals` sits under Аналитика in the
  console's own nav (`consoleNav.ts:195-197`) and belongs with that destination's items.
- Re-masking. Nothing in the product does it; the row stays revealed until the screen is left.

## Done when

- [ ] A masked phone on Клиенты shows a Показать control; an unmasked one does not.
- [ ] Revealing writes an audit record whose surface names Android, confirmed by reading
      `/calendar/phone-reveals` in the console after doing it on a real device.
- [ ] A customer with more than one row on screen is revealed once, on all of them.
- [ ] A refusal leaves the number masked and says why.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
