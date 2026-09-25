# 26-132 · Booking customer name is lost between the chat booking form and the calendar booking

- **Stage**: 26 — bug. Confirmed user-facing on the stand (Записи shows a phone, no name).
- **Status**: ready — analysis first (this item), then a fix once the drop point is pinned.
- **Found**: 2026-09-25, author: the in-chat/widget booking form requires name + phone + email (all three
  mandatory), yet `Ago.Calendar.Api`'s ConfirmedBooking has no `customerDisplayName` for the resulting
  booking — so the name is being dropped somewhere in the chat→calendar handoff, not merely "not collected".
  (The `26-112` design pass already hinted at this: "the chat→calendar carryover writes phone only".)

## Analyse (end to end, name the exact drop point)
Trace the name from entry to storage and find where it is lost:
1. **Entry form** — the booking module form (widget and/or in-chat): does it collect a name, and is it
   really required? (ago-widget booking module / the chat booking task's steps — `ChatBookingTaskState`,
   the step factory.)
2. **Chat module task** — how the collected fields travel (`ModuleTask`, the reply/confirm handler —
   `ReplyToModuleTaskHandler` around the booking confirmation).
3. **Chat → calendar carryover** — the call that creates the calendar booking from the chat task
   (`ChatBookingTask`, the module→calendar contract): are name AND phone AND email all forwarded, or only
   some? This is the prime suspect.
4. **Calendar side** — `Ago.Calendar` booking creation (`BookEvent`/`customers.display_name`): does it
   accept and persist a name if one is sent?

Deliverable: the exact file/line where the name is present on one side and absent on the other, a one-line
statement of the drop, and a proposed fix (which contract field / mapping to add), plus whether email is
also dropped. Do NOT implement yet — report the diagnosis and the fix shape.

## Done when
- [ ] The drop point is named with evidence; the fix is proposed (contract/mapping change), with a note on
      whether phone/email are affected too; a follow-up implementation ticket is filed from the finding.

---

## Diagnosis (Opus trace, 2026-09-25) — two flows conflated, two real drops

**Wording correction:** the widget booking module has NO form of its own — it renders only the primitives
the calendar sends (phone-only). The mandatory name+phone+email form is the separate **contact-capture**
control (`ago-widget/src/ui/contactCapture.ts`, `23-58`), which stores AGO Chat `VisitorContactDetail`
rows (Name/Phone/Email) — a chat-identity form, not the booking.

The booking flow is a separate step machine collecting only a phone, so the name is lost twice:
- **Drop 1 (definitive for chat bookings):** `ago-calendar` `ReplyToModuleTaskHandler.cs:409-412` books with
  `DisplayName: null`; `ChatBookingTaskState` = Service→Worker→Date→Slot→Phone→Completed (no name/email
  step); `ChatBookingTask` stores phone only. The calendar side would persist a name if supplied
  (`BookEventHandler`→`BookingStore` writes `customers.display_name`; read store projects it) — never given.
- **Drop 2 (cross-boundary loss):** name+email are collected + published for every kind via `ContactCollected`
  (`ago-chat`), but `ago-calendar` `ContactCollectedConsumer.cs:70-74` discards every kind except Phone, and
  the phone upsert never writes `display_name`. Trickier to fix: customer keyed on `source_contact_id` = the
  phone detail id; a Name detail has a different id, so correlating needs a shared visitor/conversation key.

**Email:** collected + mandatory but the calendar has NO destination — no email column on `customers`, no
email on `BookEvent`/`BookEventRequest`/`BookingAttempt`. New additive change if email must be on a booking.

## Fix options (author's call)
- **A** — collect the name inside the booking flow (add `AwaitingName` + a name `FormStep`, forward as
  `BookEvent.DisplayName`). ago-calendar only, one small migration. Reliable for all new chat bookings;
  downside: may re-ask the name that contact-capture already has.
- **B** — reuse the name already collected (contact-capture) by correlating to the booking via a shared
  visitor/conversation key (fix Drop 2 properly). No re-ask, best UX, bigger change.
- **Email** — separate larger ticket (new column + contract + step), only if email must be on a booking.

Implementation ticket filed once the author picks A vs B (+ email scope).
