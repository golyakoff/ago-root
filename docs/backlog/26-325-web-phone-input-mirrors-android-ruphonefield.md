# 26-325 · [console+widget] web phone input & display must mirror the Android RuPhoneField exactly

- **Stage**: 26
- **Status**: approved (author 2026-09-30) — implement
- **Found/decided**: 2026-09-30. Android has the canonical masked phone field (`RuPhoneField`, 26-305/307).
  The web surfaces (console `PhoneInput`/`phoneFormat`, widget `phoneFormat`/`contactCapture`) format RU
  numbers but present the country code as a separate `🇷🇺 +7` chip beside `(9XX) XXX-XX-XX`, not the
  Android inline form. Author: make the web behave **identically to Android — both on input and on
  formatted display** — code differs per platform, behaviour must match.

## Canonical spec (mirror Android `RuPhoneField.kt` / `formatRuPhoneForDisplay`)

Read `ago-android/app/src/main/kotlin/ago/chat/android/ui/components/RuPhoneField.kt` as the source of truth.

**Input:**
- Canonical value = blank while nothing typed, else `+7` + up to 10 national digits.
- Normalise on every keystroke AND paste (one path): digits only; drop one leading `8` or `7` country
  marker when the run is >10 digits; cap at 10. So `89211234567`, `+7 921 123-45-67`, `7 9211234567`,
  `9211234567` all collapse to `9211234567`.
- Mask **inline**: `+7 (XXX) XXX-XX-XX`, with a fixed, non-deletable `+7` in the field itself (DROP the
  separate `🇷🇺 +7` chip so the field matches Android). Caret stays put as punctuation is inserted ahead
  of it (mirror `maskedOffsetForDigitCount`/`digitCountForMaskedOffset`).
- Completeness gate = exactly 10 national digits (the web equivalent of `isRuPhoneComplete`), used for
  submit/search enable, not `isNotBlank`.
- Foreign passthrough: a value starting with `+` and not `+7` is left as free text, unmasked (keep the
  existing `isExplicitNonRussianPhoneValue` escape hatch).

**Display:** a `formatRuPhoneForDisplay` equivalent — render `+7 (916) 222-22-22` only when the value
unambiguously names a complete RU number, otherwise return it unchanged (foreign/incomplete passthrough).
Apply it everywhere a phone is shown (console contact/booking rows; widget wherever a phone renders),
matching where Android's 26-307 applied it.

## Slices

- **26-326** — ago-console: rework `PhoneInput`/`phoneFormat` to the inline `+7 (…)` mask + canonical
  value + completeness gate (drop the chip), and apply the display formatter at every phone render site.
- **26-327** — ago-widget: same for `phoneFormat.ts`/`contactCapture.ts` (drop the chip, inline `+7`),
  and the display formatter wherever phones show; respect the 45 KB bundle ceiling (hand-rolled, no lib).

## Done when

- [ ] Console & widget phone fields render/behave byte-for-byte like Android: inline `+7 (XXX) XXX-XX-XX`,
      same normalisation (8/7 drop, cap 10), same completeness gate, same foreign passthrough.
- [ ] Displayed phones read `+7 (916) 222-22-22` everywhere (RU), foreign unchanged.
- [ ] No `🇷🇺 +7` chip beside the field any more.
- [ ] Gates green each repo; no new phone library (hand-rolled, mirroring Android's ~40-line approach).
