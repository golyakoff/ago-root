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
