# 26-121 · [calendar] ConfirmedBooking has no SMS-confirmation state and no source/channel field

- **Stage**: 26 — surfaced implementing `26-117` (the Записи detail sheet).
- **Status**: done — the source/channel field shipped (ago-calendar#75, bound on Android in
  ago-android#133). SMS-confirmation was split to a follow-up because there is no backing data for it yet.
- **Found**: 2026-09-25, building the booking-detail sheet: the approved mockup shows a «Подтверждён по
  SMS» row and an «Источник» row, but `ago-calendar`'s `ConfirmedBookingResponse` (`ConsoleContracts.cs`)
  carries **neither** — no SMS-confirmation timestamp/flag and no booking source/channel field (the only
  `Source` in that file belongs to the unrelated `CustomerMergeCandidateResponse`). 26-117 renders both
  rows with «—» rather than fabricating data.

## Scope

- Add to `Ago.Calendar.Api`'s confirmed-booking (and detail) contract:
  - an **SMS-confirmation** signal (whether/when the booking was confirmed by SMS) — decide flag vs
    timestamp against how the calendar records it today;
  - a **source/channel** field (Виджет на сайте / Telegram / Макс / operator, etc.) — align with how the
    booking's origin is represented, and with `26-112`'s `origin_conversation_id` work (a chat-created
    booking's source is the chat channel).
- Populate them from the real calendar state; migration only if a column is genuinely missing.
- Then Android 26-117's «Подтверждён по SMS» / «Источник» rows show real values (a tiny client follow-up
  to bind the new fields — file when this lands, or fold in).

## Out of scope

- The Android detail sheet layout (done in 26-117).
- `origin_conversation_id` (26-112 GAP-C1) — related but separate.

## Done when

- [~] `ConfirmedBookingResponse` (and the detail contract) carry SMS-confirmation state and a source/channel
      field, populated from real data. — the source/channel field shipped (ago-calendar#75, origin exposed
      in ago-calendar a7842ee). SMS-confirmation was intentionally split to a follow-up: the calendar
      records no SMS-confirmation data today, so there is nothing to populate.
- [~] `ago-calendar` format/build/test green; a test covers both fields. Android binds them (here or a
      filed follow-up). — ago-calendar#75 green with a test for the source field; Android binds it
      (ago-android#133). The SMS field is deferred to the follow-up along with box 1.
