# The gate checks that everything is translated, and the calendar console gets a language at all

- **Stage**: 11
- **Status**: ready
- **Raised by**: the author, 2026-09-02 — *"в аудит по фронту надо добавить ещё что всё переводится
  на русский (кроме страниц доступных ТОЛЬКО platform owner)"*.
- **Builds on**: `15-11` (the rendered gate this check joins), `11-11`…`11-13` (the string mechanism
  `ago-console` already has).

## The check that was asked for

A fourth assertion in `15-11`'s gate: **on a screen rendered in Russian, no user-facing text is left in
another language.** Platform-owner-only screens are exempt — they are seen by one person who wrote
them.

## What checking it first revealed

The two consoles are in completely different states, and the check would say so loudly:

- **`ago-console` is localised.** `i18n/en.ts`, `i18n/ru.ts`, `StringsContext`, `resolve.ts` and three
  locale test files. `11-11`, `11-12` and `11-13` finished the shell, the operator workspace and the
  site-configuration screens. The check here is a regression guard, and should pass on day one.
- **`ago-calendar-console` has no localisation at all.** No `i18n` directory, **zero** references to a
  string table, every label written inline in English: `Workers`, `Slots`, `View slots`,
  *"What this worker's schedule actually produced"*. `15-11`'s own screenshots show the result —
  `Иванова А. П.'s slots`, a Russian name carrying an English possessive.

**That is the more important half of this item.** The first tenant is a Russian-speaking single-person
business, and the console she will open every day is entirely in English with no mechanism to be
otherwise. Adding the check without fixing that would produce a permanently red assertion, which is
the failure mode `ago-calendar-console#26` already exists to unwind.

## How to make the check precise rather than noisy

The hard part is telling **interface text** from **data** — a customer really may be called *John*, and
a brand name is not a translation failure.

**Seed every fixture in Cyrillic.** The gate already controls all data on screen (`ux-gate/fixtures/`),
so with names, services and notes written in Russian, **any Latin-script run left on the page is by
definition interface chrome**. That turns a fuzzy heuristic into an exact one, and it costs nothing but
editing a fixture file.

Exemptions, each named rather than pattern-matched:

- Platform-owner-only screens — `/owner` in `ago-console`, gated by `RequirePlatformOwner` server-side
  and `useOwnerEligibility` in the navigation.
- The product name itself, and any string that is a technical identifier a translator must not touch
  (a URL, a header name, a status code).

## Scope

- A fourth assertion in `15-11`'s gate, sharing its `lib/` shape, run at both viewports.
- Fixtures re-seeded in Cyrillic in both consoles, which is what makes the assertion exact.
- **`ago-calendar-console` gains the string mechanism `ago-console` already has** — `en`/`ru` tables,
  a context, locale resolution — and its screens are translated. Reuse `11-11`'s shape rather than
  inventing a second one; it is the same problem, already solved once next door.
- An exemption list that is a **named list**, not a regular expression over "words that look
  technical".

## Out of scope

- `ago-widget`. It has its own locale mechanism already (`11-10`: `widgetLocale` arrives on the
  session response), and its surface is three buttons and a composer. Worth checking eventually; not
  what this item is about.
- Any language beyond the two already modelled.
- Extracting a shared string mechanism into a package. Same reasoning as `11-14`: two consoles, no
  shared package, and 84 tokens against 5 — the shared layer is not decided under launch pressure.

## Done when

- [ ] A screen rendered in Russian with Cyrillic fixtures shows no Latin-script interface text, in
      both consoles, at both viewports — and the assertion is **proven to fail first** against a
      deliberately untranslated label.
- [ ] `/owner` is exempt, and the exemption is a named list a reader can audit — not a pattern.
- [ ] `ago-calendar-console` has a string table and a locale context, and every screen `15-11` gates
      renders from it.
- [ ] Switching locale changes the rendered text, proven by a test rather than by the table existing.
- [ ] `15-11`'s existing three assertions stay green in every repository they are green in today.

## Open questions

- **What decides the locale in `ago-calendar-console`?** `ago-console` resolves it per tenant. Calendar
  has its own tenant record and may reasonably do the same — but "may reasonably" is how two products
  end up resolving the same thing two ways, and `adr/0027` is the standing warning about exactly that.
- **Does an English string on a Russian screen fail the build, or warn?** The gate's other assertions
  fail. An untranslated label is less severe than an unreachable control, and this item does not
  presume the answer — but it should be decided rather than inherited.
- **Is the tenant-facing booking widget in scope later?** It is the surface a *customer* sees, which
  makes it more exposed than either console, and nobody has looked at its localisation at all.
