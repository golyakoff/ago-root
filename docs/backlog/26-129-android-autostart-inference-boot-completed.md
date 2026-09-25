# 26-129 · [android] Infer "didn't autostart after reboot" via a BOOT_COMPLETED marker (autostart follow-up)

- **Stage**: 26 — follow-up to `26-128` (autostart status is otherwise unreadable on AOSP).
- **Status**: ready — lower priority; the honest after-the-fact signal.
- **Found**: 2026-09-25, designing `26-128`.

## Idea
Autostart has no AOSP read API, so `26-128` shows it as a recommendation. This adds a real, if imperfect,
signal: register a `BOOT_COMPLETED` receiver; on boot, record it. Compare an approximate last-boot time
(`System.currentTimeMillis() - SystemClock.elapsedRealtime()`) against a stored "last seen boot" marker: if
the phone rebooted but the app's `BOOT_COMPLETED` never ran before the user's next manual open, that is
evidence autostart was blocked — flip the «Автозапуск» row to orange with a specific reason («не запустился
автоматически после последней перезагрузки»). Inference after the fact, never a live/proactive read.

## Done when
- [ ] After a real reboot where autostart was blocked, the «Автозапуск» row honestly reflects it with the
      specific reason; where it did autostart, it does not falsely warn.
- [ ] Tests for the boot-marker comparison logic; suite green.
