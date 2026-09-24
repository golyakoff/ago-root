# 26-105 · Elapsed-time plurals use Russian grammar regardless of the active language

- **Stage**: 26
- **Status**: done — merged as [ago-android#97](https://github.com/golyakoff/ago-android/pull/97).
- **Found**: 2026-09-24, landing `26-92` (the in-app language switch). Named in `ago-android`'s
  `docs/architecture.md` as work `26-92` or a companion item must do before English is ever shown.

## What is actually true today

`ago-android` `app/src/main/kotlin/ago/chat/android/ui/components/ElapsedText.kt`'s
`russianPluralStringResource()` chooses the plural bucket with Russian mod-10 / mod-100 grammar (one /
few / many) for **every** locale. While the app was Russian-only this was correct. `26-92` now lets an
operator pick English, and English has a different plural rule (one / other) — so elapsed-time labels
like "21 minute", "2 minutes", "5 minutes" will render with the wrong form once English is active
(Russian's rule would say "21 minute" is the singular bucket, which is right for Russian «21 минута»
but wrong for English "21 minutes").

## Scope

- `ago-android`: select the plural form by the **active locale's** rules, not always Russian. Prefer
  Android's own plural resources (`<plurals>` / `getQuantityString`), which apply the correct CLDR
  plural rule per locale automatically — replacing the hand-rolled Russian selection where it is used
  for user-facing elapsed/relative-time text. If a hand-rolled path must stay, branch it on the active
  locale.
- Provide the plural forms for both ru and en (26-91), with the correct quantity keys per language.

## Out of scope

- The language switch itself (`26-92`, done) and any other locale-sensitive formatting that is not
  plural-rule-based (dates/numbers already go through platform formatters).

## Done when

- [x] Elapsed/relative-time labels render the correct plural form in both Russian and English —
      verified by a test that exercises the same counts under each locale (e.g. 1, 2, 5, 21).
- [x] The Russian output is unchanged from today (no regression for the current default).
- [x] `./gradlew ktlintCheck lint test` green.
