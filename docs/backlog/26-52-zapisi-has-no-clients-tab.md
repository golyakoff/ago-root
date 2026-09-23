# 26-52 · Записи has no Клиенты tab

- **Stage**: 26
- **Status**: ready
- **Depends on**: `26-48` (the calendar API client and the Записи segmented control)
- **Found**: 2026-09-23, reading `ago-console/src/pages/CalendarContactsPage.tsx` against the approved
  mockup Artifact ("AGO Chat для Android", `8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`) §04's own
  three-segment control, and `ago-android` `main` at `b099282`.

## Found

The mockup's Записи carries three segments — Ожидают, Утверждены, **Клиенты** — and the third is the
tenant's own customer base: who has booked here, how reachable they are, and how often they did not
turn up. `26-48` and `26-51` build the first two. This is the third, and it is the smallest of them.

## What is actually true today, confirmed against real code

- `app/src/main/kotlin/ago/chat/android/shell/PlaceholderScreens.kt:50-55` — nothing exists.
- `ago-console/src/pages/CalendarContactsPage.tsx`:
  - The gate is `calendar:configure` **or** `customer:read` (`:48`), a third distinct gate from the
    other two segments' — which is why the segmented control genuinely has to be computed rather than
    drawn as a fixed three.
  - The read is `getContacts(token)` (`calendarApi.ts:685`), returning `Contact`
    (`calendarApi.ts:367`), one row per customer.
  - The phone column goes through the shared `renderPhone` (`:160`,
    `ago-console/src/calendar/calendarFormat.tsx`), which draws a Показать control exactly when
    `masked` is true — never inferred from the string's own shape.
  - Two further columns render `phoneVerifiedAt` and `phoneConfirmedByOperatorAt` as **separate**
    badges (`:33-36`): "proven reachable by SMS" and "an operator called and it is them" are two
    different facts and the console deliberately never merges them.
  - Merging two customers is gated separately again, on `customer:edit` (`:53`).
- The mockup's own identity treatment for a nameless customer is this app's established one — an emoji
  pair and eight monospace characters — and `IdentifierText` (`ui/components/IdentifierText.kt:26-36`)
  is already the one place that is rendered.

## Scope

One promise: **Клиенты lists this tenant's real customers, read-only, with phones left masked.**

1. The segment appears for `calendar:configure` or `customer:read`, matching
   `CalendarContactsPage.tsx:48`.
2. A card list — name (or the identifier, honestly, when there is none), the masked phone as the
   server returned it, and the no-show count read plainly.
3. **The two phone-assessment facts stay two facts.** Whatever they become visually on a card, they
   never collapse into one "verified" badge. The console's own comment says why, and a smaller
   viewport is exactly where the temptation to merge them arises — the identical rule
   `scope-inventory.md` §9 already states for `/account/ai`'s three controls.
4. Masked is masked. The card shows the masked form and draws no reveal control at all this item; see
   Out of scope.

## Out of scope

- **Показать, the audited reveal.** `26-53`. It is a write (it records who saw what, `adr/0161`'s
  neighbourhood) and it is a separate promise; a list whose phones are masked is still a useful list,
  because the names and the no-show counts are the part an operator actually scans.
- **Объединение клиентов.** Gated separately (`customer:edit`), irreversible, and the console's own
  copy about that is kept verbatim on purpose. It needs its own item and its own care.
- **The client card** (`ClientCard` in the mockup's graph). A row that opens nothing is fine here —
  the list is the answer.
- Ожидают and Утверждены.

## Done when

- [ ] An operator holding `customer:read` sees the Клиенты segment and the tenant's real customers.
- [ ] A customer with no recorded name renders through `IdentifierText`, never as a full GUID and
      never as an invented label.
- [ ] `phoneVerifiedAt` and `phoneConfirmedByOperatorAt` are visibly two separate facts.
- [ ] No unmasked phone number reaches the screen from this item.
- [ ] An empty customer base renders a stated empty state.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green.
- [ ] Checked on a real device against a tenant with at least one named and one nameless customer.
