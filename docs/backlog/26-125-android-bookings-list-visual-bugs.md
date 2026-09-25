# 26-125 · [android] Записи→Утверждены list visual bugs (time truncated, master not uppercase, missing dot, unmasked phone)

- **Stage**: 26 — fixes on the shipped `26-117` screen, found on the deployed APK.
- **Status**: ready.
- **Found**: 2026-09-25, author on device (screenshot).

## Bugs (all on `ConfirmedBookingsScreen.kt`)

1. **Time truncated: «10:0» instead of «10:00».** The leading fixed-width time column is too narrow (or
   clips) — widen it / stop clipping so a full `HH:mm` always fits.
2. **Master group header is not UPPERCASE.** `WorkerGroupHeader` renders `"${workerDisplayName} · <count>"`
   in normal case; the approved mockup shows it uppercase («ИРИНА СОКОЛОВА · 4 записи»). Apply an
   uppercase transform (locale-aware) / the mockup's caps label style.
3. **Service · duration separator missing.** The row shows "Услуга␣␣длительность" with a gap; the mockup is
   «Услуга · длительность» joined by a middot. Restore the `·` separator.
4. **Fallback phone is shown UNMASKED.** `ConfirmedBookingIdentity.MaskedPhone` renders the phone "exactly
   as the server sent it" — and `Ago.Calendar.Api` sends it unmasked, so the list shows a full
   `+79162911129`. Mask it for the list (client-side mask, or respect a `masked` field if the payload
   carries one) — a full phone number must not be the row's visible identity.

## Note (not a bug of this ticket)
The **empty customer name** (why the phone shows at all) is the missing name-collection flow — `26-112`
backend, not yet built. This ticket only ensures the fallback is correct (masked); populating names is
`26-112`.

## Done when
- [ ] Full `HH:mm` shows; master header uppercase; «Услуга · длительность» with the dot; fallback phone
      masked (no full number on the list).
- [ ] `./gradlew ktlintCheck lint test :app:compileDebugAndroidTestKotlin` green; a test for the mask +
      the time format; counts reported.
