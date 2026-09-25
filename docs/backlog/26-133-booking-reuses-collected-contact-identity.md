# 26-133 · A booking reuses the already-collected contact identity (name/email), and cannot complete without it (26-132 fix B)

- **Stage**: 26 — fix **B** for `26-132` (author chose B, not A: never re-ask the visitor for data they
  already gave — re-entry drives clients away).
- **Status**: ready — direction decided.
- **Supersedes**: the A option (a name step in the booking flow) and `26-112`'s proposed `26-150`.

## What and why (from the 26-132 diagnosis)
The visitor already gives name+phone+email once, in the **contact-capture** form (`23-58`), stored as AGO
Chat `VisitorContactDetail` rows and published via `ContactCollected` (every kind). But the booking is
created with `DisplayName: null`, and the calendar's `ContactCollectedConsumer` drops every kind except
Phone (and never writes `display_name`). So the collected name/email never reach the booking. The author's
decision: **reuse the collected identity — do not re-ask** and **do not let a booking complete without the
contact form**.

## Scope
1. **Correlate the collected identity to the booking by a shared visitor/conversation key**, NOT by
   `source_contact_id` (that is the phone detail's id — the trap the 26-132 trace flagged; a Name detail has
   a different id, so a naive filter-widen makes a second customer row instead of filling the name). The
   natural shared key is the chat conversation/visitor id — the SAME key `26-112`'s `origin_conversation_id`
   booking↔dialog link needs, so design them together / reuse it. Decide the key, state it.
2. On the calendar side: the customer/booking for a chat booking must carry the **name** (and **email**)
   the visitor gave — persist `customers.display_name` from the collected Name; add an **email destination**
   (new `customers.email` column + contract field) so email is not lost either (author does not want email
   re-asked; it must land somewhere). Migration(s) via the calendar migration lane.
3. **Guarantee a booking cannot complete without the contact form** — if the contact-capture (name+phone+
   email) can currently be skipped before a booking completes, close that hole here (this is where the
   "unreliability" the author named must be fixed). A booking that reaches `Completed` must have a name.
4. No re-asking anywhere; the booking flow does NOT gain a name/email step (that was rejected option A).

## Out of scope
- The Android render (already shows the name when present, 26-117).
- BOOT_COMPLETED / battery items.

## Done when
- [ ] A chat booking's calendar customer carries the name (and email) the visitor entered in contact-capture,
      correlated by the shared visitor/conversation key — no second customer row, no re-ask.
- [ ] A booking cannot reach Completed without the contact form (name present); proven by a test.
- [ ] Migrations via the calendar lane; ago-chat + ago-calendar suites green; a test proves the name (and
      email) round-trip from contact-capture to `ConfirmedBookingResponse.customerDisplayName`. Counts reported.
