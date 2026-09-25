# 26-121 · [calendar] ConfirmedBooking has no SMS-confirmation state and no source/channel field

- **Stage**: 26 — surfaced implementing `26-117` (the Записи detail sheet).
- **Status**: ready — additive contract fields; the Android detail sheet already renders honest «—»
  placeholders for them, so this fills real data in, no client redesign needed.
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

- [ ] `ConfirmedBookingResponse` (and the detail contract) carry SMS-confirmation state and a source/channel
      field, populated from real data.
- [ ] `ago-calendar` format/build/test green; a test covers both fields. Android binds them (here or a
      filed follow-up).
