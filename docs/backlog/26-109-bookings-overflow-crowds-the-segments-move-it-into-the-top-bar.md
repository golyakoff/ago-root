# 26-109 · The Записи overflow «⋮» crowds the segmented tabs — move it into the top bar next to the avatar

- **Stage**: 26
- **Status**: ready — direction decided (see below); a small single-file layout move.
- **Found**: 2026-09-25, by the author, live on a real phone. The «⋮» config menu sits in the second
  row alongside the segmented control, eating enough width that «Утверждены» wraps to two lines and the
  three segments «Ожидают | Утверждены | Клиенты» no longer fit on one row.

## What is actually true today, confirmed against the real code

`BookingsScreen` (`ago-android`, `app/.../bookings/BookingsScreen.kt`) draws:
- a `TopAppBar` whose `actions` already contains the shared `AccountAvatarAction` (the «AG» avatar), and
- a second `Row` below it holding `SingleChoiceSegmentedButtonRow(Modifier.weight(1f))` **and**
  `BookingsConfigMenu` (the «⋮» `IconButton` + `DropdownMenu`, entries Услуги/Часы) side by side.

Because the «⋮» shares the segment row, the segmented control loses that width and «Утверждены» wraps.
`26-103` moved Услуги/Часы out of the segmented control into this overflow precisely so at most three
segments ever render — but the overflow was placed in the segment row, which re-introduces the crowding
it was meant to remove.

## The decision (why "customize this screen", not "a shared 3-dots header")

A shared header component that owns a «⋮» was considered and rejected: the overflow's **contents are
screen-specific** (Записи's are Услуги/Часы; another screen's would differ), so there is nothing
shareable about the menu itself — only its *placement*. The shared piece already exists and is already
reused: `AccountAvatarAction`. The right shape is therefore the standard Material one — **screen-specific
overflow lives in that screen's own `TopAppBar` `actions`, to the left of the persistent avatar action** —
which is "customize this screen" reusing the shared avatar, and it establishes the placement convention
(overflow left of the avatar in the top bar) for any future screen that grows an overflow, without a new
component that would only ever wrap one screen's items.

## Scope

- Move `BookingsConfigMenu(...)` out of the second `Row` and into the `TopAppBar` `actions`, placed
  **before** `AccountAvatarAction` (overflow sits left of the avatar). Keep its "hide, don't disable when
  empty" behaviour (`if (entries.isEmpty()) return`) — in the top bar it simply renders nothing when
  there are no Услуги/Часы entries.
- The second row then holds only the `SingleChoiceSegmentedButtonRow`, taking the full width (drop the
  now-pointless `weight(1f)`/`Row` wrapper if it serves nothing else; keep the horizontal/vertical
  padding the row had).
- No string changes; `bookings_config_menu_action` content description is unchanged.

## Out of scope

- Introducing a new shared top-bar/header composable (rejected above).
- Any change to the overflow's menu entries, the segments themselves, or other screens' top bars.

## Done when

- [ ] The «⋮» renders in the `TopAppBar` next to the «AG» avatar; the three segments
      «Ожидают | Утверждены | Клиенты» fit on one row with no wrapping.
- [ ] `BookingsConfigMenu` still self-hides when it has no entries.
- [ ] `./gradlew ktlintCheck lint test` green and `:app:compileDebugAndroidTestKotlin` compiles; existing
      Bookings tests updated if they asserted the old placement.
