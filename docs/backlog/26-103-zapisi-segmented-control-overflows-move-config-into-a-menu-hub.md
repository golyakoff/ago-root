# 26-103 · The Записи segmented control overflows — move configuration into a ⋮ menu/hub

- **Stage**: 26
- **Status**: ready — designed and approved by the author 2026-09-24; the design is in the reference
  artifact.
- **Found**: 2026-09-24, by the author on a real device — a screenshot of Записи with the segmented
  control wrapping badly. `26-96` (Услуги) and `26-97` (Часы) each added a segment, so the control now
  carries **five** (Ожидают / Утверждены / Клиенты / Услуги / Часы) and the layout breaks.

## What is actually true today

`BookingsTab` renders every section as a segment of one horizontal segmented control. With five
segments the labels wrap and "вёрстка сильно плывёт" (author's words). The split was talked through and
settled: three of these are **operational** (a live decision with a deadline — Ожидают / Утверждены /
Клиенты), the other two are **configuration** (nothing urgent, read more than edited — Услуги / Часы,
and later Мастера / Календари).

## The design (approved)

Already drawn into the reference artifact ("AGO Chat Design", section 02 · Диалоги/Записи — the
3-segment frame with the open ⋮ popover, tagged "найдено на реальном устройстве, исправлено") and it
carries the general rule: **a segmented control never holds more than three segments; the divider is
"is there something urgent right now", not "is this used often"; the same ⋮-overflow trick applies to
any tab that starts to overflow.**

- The Записи control drops to **three** segments: Ожидают / Утверждены / Клиенты.
- A **⋮ (overflow) control** next to the segments opens an anchored menu with the configuration
  entries — **Услуги** and **Часы** for now — each opening its existing screen (`26-96`/`26-97` already
  built those screens; this item only changes how they are reached, it does not rebuild them).
- Gating is unchanged: an entry appears only for the permission its screen already requires
  (`calendar:configure`), the same "hide, don't disable" rule the rest of the app follows. If neither
  configuration entry is visible for a given operator, the ⋮ control does not appear.

This is deliberately the **minimal** first step. The fuller "Конфигурация записей" hub screen with the
booking-readiness chain (`docs/navigation.md`'s six-precondition design) is **not** this item — it is a
separate, larger, later one. This item is only: three segments + a ⋮ menu with the two entries that
already exist.

## Out of scope

- The full "Конфигурация записей" readiness-chain hub (a separate future item).
- Any change to the Услуги (`26-96`) or Часы (`26-97`) screens themselves — only their entry point moves.
- Мастера / Календари entries — added to the same menu when those screens exist, not now.

## Done when

- [ ] The Записи segmented control shows exactly three segments (Ожидают / Утверждены / Клиенты) and no
      longer wraps at any supported width.
- [ ] A ⋮ control opens an anchored menu with Услуги and Часы, each opening its existing screen; the ⋮
      control and each entry appear only for a holder of `calendar:configure` (asserted in a test, not
      only by eye).
- [ ] Matches the reference artifact's 3-segment + open-popover frame (layout and copy).
- [ ] `./gradlew ktlintCheck lint test` green; new strings are resources in both languages (`26-91`).
