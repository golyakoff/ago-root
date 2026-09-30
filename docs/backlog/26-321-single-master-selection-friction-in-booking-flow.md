# 26-321 · [onboarding/booking] the master-selection step confuses when there is only one master

- **Stage**: 26
- **Status**: needs design (opus)
- **Found**: 2026-09-30, **first real user** (Алёна, «Салон Топаз»). In the booking flow the explicit
  "choose a master" step confused her even though she is the only master — she did not realise she had to
  tap her own name to select it, and stalled on the step. This is the first feedback from a live user
  rather than the author's own testing; treat it as high-signal.

## The ask (author, relaying the user)

If there is exactly one eligible master, skip the selection step (or auto-record "the only master,
Алёна Матерн") so the flow reads clearly. With several masters the need to tap becomes self-evident, so
extra explanatory copy may not be needed. **Constraint the author flagged:** there is also a plain-text
chat booking flow, where "tap to select" copy is wrong/confusing — any solution must fit both the tap
UIs and the plain-text channel.

## What to design (options + a recommendation)

1. **Map every booking-entry surface** and how master selection is presented in each today:
   - operator **manual booking** wizard — console (`ManualBooking*` in ago-console) AND android
     (`ManualBookingScreen`/`ManualBookingViewModel`, the `26-268` flow) — this is the one Алёна used;
   - **visitor widget** booking flow;
   - **plain-text chat** booking flow (how a visitor picks a master by text).
2. Propose the single-eligible-master rule per surface: auto-select and skip the step (record it
   implicitly), or a pre-selected/one-tap-confirm variant. Decide whether the skip should also apply
   with >1 master where only one is eligible for the chosen service.
3. Handle the **plain-text** case explicitly: with one master, don't ask at all; with several, the text
   prompt already implies "reply with a number/name" — make sure no tap-only copy leaks there.
4. Copy: whether any explanatory text is needed at all (author leans no); if any, must be
   surface-appropriate (never "щёлкните" in plain text).
5. Note interactions with 26-317 (2 masters by default — so "one master" is common early but "two" is
   the default, meaning the >1 case is also immediately relevant) and 26-318 (onboarding wizard).

## Deliverable

A short design (options with trade-offs + a recommendation) the author reviews before implementation —
one consistent rule across surfaces, with the plain-text nuance resolved. No code in this item; slice(s)
filed after the author picks.

## Done when

- [ ] Design doc with surface map + recommended single-master behaviour per surface (incl. plain-text).
- [ ] Author picks the approach; implementation slice(s) filed.
