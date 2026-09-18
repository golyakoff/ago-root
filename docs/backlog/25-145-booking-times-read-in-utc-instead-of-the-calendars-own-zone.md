# 25-145 · Booking times read in UTC instead of the calendar's own zone

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18, live, reported by the author after completing a real booking end to end: the
  confirmation and every date/time choice read like "2026-09-20 13:00 UTC - 14:00 UTC" instead of the
  calendar's own local time - and the date labels ("пт, 18 сен") give no year and abbreviate both the
  weekday and the month, which the author specifically wants full for orientation ("многих клиентов
  день недели лучше сориентирует, чем просто число").
- **Depends on**: none. Touches `ago-calendar` only - `docs/backlog/25-16-*.md` (done) already built
  everything this item needs on the data side; this is a presentation-layer gap, not a missing setting.

## What is actually true today - read this before assuming new infrastructure is needed

`BookingCalendar.TimeZone` (`Ago.Calendar.Domain`, a real `CalendarTimeZone` wrapping an IANA zone id)
already exists, is already set per-calendar, and is already used correctly for the calendar's own
internal working-hours/slot-grid arithmetic (`SlotGrid`'s own remarks: "wall clock in, instants out").
`25-16` already gave tenants a real, localized dropdown to set it in `ago-console`
(`CalendarSetupPage.tsx`), covering Russia's 11 canonical federal time zones (fixed offsets, no DST
since 2014, confirmed by that item's own outcome).

**The gap is entirely in the chat-facing presentation layer.** `ModuleStepFactory`'s
`DescribeRange`/`DescribeTimeOnly` (`ago-calendar/src/Ago.Calendar.Application/UseCases/
ChatModuleTask/ModuleStepFactory.cs:196-202`) hardcode UTC, and `Strings.FormatDate` (same file,
`:298-303`) uses three-letter weekday/month abbreviations with no year. Neither ever sees the
calendar's own configured `TimeZone` - `ReplyToModuleTaskHandler` (the only caller of these methods)
never loads `BookingCalendar` at all; it works entirely through `IBookingSurfaceReadStore`'s
projection rows (`OpenSlotRow`, etc.), which carry no timezone field either.

## Scope

- Get the booking calendar's own `TimeZone` to `ModuleStepFactory` for every call that renders a date
  or a time (`DateChoice`, `SlotChoice`, `Confirmation`) - either by adding a lightweight read
  (`IBookingSurfaceReadStore` growing a `GetCalendarTimeZoneAsync`, matching that port's own "rows, not
  aggregates" posture) or by loading `BookingCalendar` once via `IBookingCalendarRepository` in
  `ReplyToModuleTaskHandler` (already used elsewhere for the write side) and passing `.TimeZone`
  through. Pick one and say why, out loud, per this project's teaching-mode convention - this is a
  real "which layer does a read belong in" call, not a foregone one.
- Convert every instant (`DateTimeOffset`) to the calendar's own zone with `TimeZoneInfo` before
  formatting - `DescribeRange`/`DescribeTimeOnly` currently format the raw UTC `DateTimeOffset`
  directly.
- Render the zone as a short Russian abbreviation ("МСК", "МСК+2", ...), never "UTC" and never the raw
  IANA id - hand-written per zone, the same "closed set, hand-written, no ICU/CultureInfo dependency"
  posture `Strings`'s own weekday/month tables already use (that table's own doc comment names a real,
  already-burned risk in this exact codebase: a deployed base image once shipped no tzdata at all,
  found by `25-26` - do not assume `TimeZoneInfo`'s own display name or an ICU-derived abbreviation is
  available or correctly localized without checking live). Cover the same 11 canonical Russian federal
  zones `25-16`'s own outcome names; anything outside that set can fall back to the bare UTC-offset
  form (e.g. "+05:00") rather than guessing an abbreviation that does not exist.
- `Strings.FormatDate` grows a year and stops abbreviating: "пятница, 18 сентября 2026", not "пт, 18
  сен" - full weekday name, full month name, four-digit year. Give the English table the equivalent
  full form too, for consistency, even though the author's own report is about the Russian rendering.
- `SlotChoice`'s own time-only label ("09:00 - 10:00 UTC" today) becomes the zone-converted range with
  the abbreviation, e.g. "12:00 - 13:00 МСК" - matching the confirmation card's own new format.
- This is one fix in `ModuleStepFactory`, so it reaches **both** consumers for free: the widget's rich
  buttons (which read these same action labels) and a text channel's plain-text rendering
  (`Ago.Chat.Domain.PrimitiveTextRenderer`, which numbers these same labels for Telegram/MAX) - no
  `ago-chat`/`ago-widget` change is needed for this item.

## Where this is likely to go wrong

- **Do not guess the visitor's own timezone from anything client-side.** `docs/conventions/
  date-and-time.md` rule 1 is explicit that no visitor IANA zone is knowable in a chat channel - the
  zone this item renders in is the *calendar's own*, a tenant-configured fact, not a guess about the
  visitor.
- Verify `TimeZoneInfo.FindSystemTimeZoneById` actually resolves every one of the 11 canonical zones
  inside the deployed container - `25-26`'s own incident (missing tzdata) is exactly the failure mode
  to rule out live, not assume fixed because the calendar's own internal arithmetic already uses it
  successfully elsewhere (confirm it is the *same* code path, not a coincidentally-working one).
- Don't touch `FormatDateValue`'s own ISO wire value (`ModuleStep`'s own `SlotOption.Value`/action
  `Value`) - only the human-readable *labels* change; the reply-matching machinery still needs the
  existing wire format untouched.

## Done when

- [ ] A booking's confirmation reads e.g. "20 сентября 2026, воскресенье, 16:00 МСК" for a
      Europe/Moscow calendar, not "2026-09-20 13:00 UTC - 14:00 UTC"
- [ ] The date-choice step's own labels read "пятница, 18 сентября 2026" - full weekday, full month,
      year - not the old three-letter abbreviations with no year
- [ ] The time-choice step's own labels read the calendar's local time with a Russian zone
      abbreviation ("12:00 - 13:00 МСК"), not UTC
- [ ] A text-channel (Telegram/MAX) delivery of the same steps shows the identical converted times and
      full-form dates, proven without any `ago-chat` change - confirming the fix lives entirely in the
      one shared label source
- [ ] English locale gets the equivalent full-form date (a documented, deliberate choice either way,
      not left unstated)
