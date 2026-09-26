# 26-161 · [console] Read the Person from chat's API; retire the calendar customer-merge UI (adr/0184 S4-console + S7)

- **Stage**: 26 — ADR-0184 (option B) front-end. Design:
  `docs/design/26-134-person-identity-implementation.md` (S4 console half + S7). Backend landed +
  deployed (chat #368, calendar #76). **Depends on**: nothing further — the chat Person API is live.
- **Status**: done — merged ago-console#279 (c73c699) and deployed to the stand (console 2315100c, smoke 43/0). Closed #1622/#1625 alongside.
- Carries the console half of the identity unification that closes #1622 (26-132) and #1625 (26-133).

## One promise
The calendar console shows a booking's person by reading the Person from chat's registry API instead
of a calendar-local customer copy, and the retired customer-merge feature is gone from the UI.

## Scope
- **Rename** `customerId` → `personId` across `src/api/calendarApi.ts` DTOs
  (`PendingBooking`/`ConfirmedBooking`/`WorkerSlot`/`RecutBookingPreview`/`Contact`/`PhoneReveal`);
  drop `customerDisplayName`/`displayName`/`notes`/`duplicatePhoneCustomerIds`; `revealCustomerPhone`
  path param becomes personId.
- **Delete** the whole `CustomerMerge*` type + function block (`getCustomerMergePreview`/
  `mergeCustomers`/`getCustomerMerges`).
- New `src/api/personsApi.ts`: chat Person read client (`GET ${apiBaseUrl}/api/v1/persons?ids=`,
  operator token + active-site header).
- **Display-merge** in the consumers (`CalendarContactsPage`, `CalendarBookingsPage`,
  `CalendarQueuePage`, `CalendarWorkerSlotsPage`, `CalendarWorkerRecutPage`,
  `CalendarPhoneRevealsPage`, shared `calendar/calendarFormat.tsx`): fetch person names by id, merge
  by `personId`, per-row loading state, and degrade to "name not shown yet" when the Person API is
  unreachable (ADR-0184).
- **Remove** `CalendarCustomerMergesPage.tsx` + `.test.tsx` + `CustomerMergeDialog.tsx` + the
  `/calendar/customer-merges` route + nav entry + merge i18n strings (`i18n/en.ts`,`ru.ts`).
- Update all page tests + fixtures; the ux-gate Playwright fixtures need a stub for the new chat
  person endpoint.

## Done when
- [x] Console reads person names from chat's API, degrades gracefully; merge UI removed; all callers
      updated; `npm run typecheck && npm run lint && npm run test && npm run ux-gate` green (test 1687, ux-gate 67).
- [x] Deployed to the stand (`deploy.sh console 2315100c`) after merge — smoke 43/0.
