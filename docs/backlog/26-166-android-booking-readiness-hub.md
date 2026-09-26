# 26-166 · [android] Booking-readiness hub «Может ли клиент записаться?» (was placeholder 26-154)

- **Stage**: 26. Design: `docs/design/26-154-android-booking-readiness-hub.md` (the scoping pass;
  premise verified — backend `GET /booking-readiness` exists in full, Android has nothing yet, no
  backend change / no migration needed).
- **Status**: ready. Product decisions taken (author accepted the scoping doc's recommendations,
  2026-09-26): own `⋮` entry «Готовность» first in the menu; short label «Готовность» with the full
  question as the page title; «Исправить» does an in-hub swap (back → Записи); re-read on open + retry
  (no pull-to-refresh); interim `ScheduleSaved`/`SlotsMaterialized` targets point at the Masters list
  until 26-155 lands.

## One promise
The Android app surfaces the calendar booking-readiness chain (can a client book? what's missing?) on a
«Готовность» screen reached from the Записи `⋮` hub, reading `GET /booking-readiness`.

## Scope
- New readiness client in `core/**` over `GET /booking-readiness` (confirm the exact DTO from the
  calendar backend). Parallel-safe (core-only).
- «Готовность» screen: the readiness chain with per-step state; «Исправить» in-hub swap to the relevant
  config screen; re-read on open + retry-only. Wire into the Записи `⋮` hub as the first entry
  (`showSetupSegment`/gating threaded the same way as the other hub screens; audit surface names per the
  design doc). Reuse the app's existing design language/fonts/weights.
- Strings both languages; no literals.

## Done when
- [ ] «Готовность» screen reads booking-readiness, renders the chain, «Исправить» navigates, gated +
      appears in the `⋮` hub; `ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; strings
      both languages.
