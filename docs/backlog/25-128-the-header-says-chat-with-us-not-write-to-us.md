# 25-128 · The header says "chat with us", not "write to us"

- **Stage**: 25
- **Depends on**: nothing
- **Status**: ready
- **Found**: 2026-09-17, the author's own wording preference for the widget's fixed header title.

## Scope

- `i18n/ru.ts`'s `chatWithUs: "Чат с нами"` becomes `"Напишите нам"`. Check `i18n/en.ts`'s own English
  copy ("Chat with us") for whether an equivalent wording change was intended too, or whether this is
  Russian-only - the author's own request named only the Russian text; ask in the report rather than
  guess if genuinely ambiguous, but the default is Russian-only since that is what was asked.
- The string key (`chatWithUs`) stays as-is - only the value changes. Renaming the key is unnecessary
  churn for a one-line copy change.

## Done when

- [ ] The Russian widget header reads "Напишите нам".
- [ ] No other string, test, or snapshot still asserts the old "Чат с нами" text.
