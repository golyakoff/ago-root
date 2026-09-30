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

## Extension (author, 2026-09-30): skip the SERVICE step too when there is only one service

Same rule, applied one step earlier: if the tenant has exactly one selectable service, auto-select it
and skip the service step — it is shown on the review/confirmation card at the end, exactly like the
master. Compose the two skips in flow order: `service (skip if 1) → master (skip if 1 eligible for that
service)`. For a solo tenant (one service + one master) both steps vanish: phone → client → date → slot
→ review. Keys on the **eligible/selectable list length = 1** for each step (not a global "does the
tenant have one thing"), consistent with the master rule and correct under 26-317's 2-master default.
No new copy; the confirmation card already names the service and the master.

## Approach APPROVED (author) — implementation slices

Author approved the single-eligible auto-skip approach (no new copy), extended to the service step.
Filed as three independent slices (different repos/files, no migration):

- **26-322** — `ago-calendar`: in the visitor/chat state machine (`ReplyToModuleTaskHandler`), skip the
  service-choice step when one selectable service AND the worker-choice step when one eligible worker;
  covers widget + plain-text at once. Preserve `25-32` replay-safety across the auto-skips
  (concurrency-review). Highest leverage.
- **26-323** — `ago-console`: manual-booking wizard (`ManualBookingButton.tsx`) skip service and worker
  steps when their eligible list is 1; fix back-navigation across skipped steps.
- **26-324** — `ago-android`: manual-booking wizard (`ManualBookingViewModel`) same skips in
  `selectService`/`selectWorker` + fix `back()`.

26-321 stays as the design-of-record; it closes when 26-322/323/324 land.
