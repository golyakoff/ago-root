# 26-79 · The app has no second interface language to switch to

- **Stage**: 26
- **Status**: done — decided by the author, 2026-09-24: build it, split in two per `CLAUDE.md` rule 15
  (one quick promise — every string is a resource in both languages — and one real feature — the switch
  itself). Carried out to `26-91` (the resources) and `26-92` (the switch, depends on `26-91`).
- **Found**: 2026-09-23, while scoping `26-77` (the account menu). The author asked to record that the
  app's own "Язык" setting is the interface language, distinct from the widget's own language — while
  writing that item, checking what a "Язык" row in Settings would actually take to build for real
  turned up that there is nothing to switch to yet.

## What is actually true today, confirmed against real code

- `app/src/main/res` has exactly one resource directory: `values/`. No `values-en/`, no `values-<any
  other locale>/`. Every string in this app exists in Russian only.
- No runtime locale-switching infrastructure anywhere in `app/src/main/kotlin`: no
  `AppCompatDelegate`/`setApplicationLocales`/`LocaleListCompat` usage at all (grepped the whole
  module, zero hits).

So "Язык интерфейса: Русский / English" — drawn in the mockup Artifact's own new Настройки screen
(section "08 · Аккаунт и шапка", `https://claude.ai/code/artifact/8b4fb3a8-ddc0-4b2f-81ce-81d13c30a9d3`)
as the target design — is not a Settings row away from existing. It needs, at minimum: a full English
translation of every user-facing string in the app, and real runtime locale-switching (most simply,
Android 13+'s per-app language API via `AppCompatDelegate.setApplicationLocales`, with whatever
fallback this app's own `minSdk` requires for older devices).

## The one thing this item does settle, since the author asked for it explicitly

**Decided, 2026-09-23**: whenever this is built, the app's own "Язык интерфейса" setting is the
*operator app's own interface language* — button labels, screen titles, system messages inside this
Android app. It is a **different, independent setting** from the widget's own language (a per-site
configuration in the console, unrelated to this app), which governs what language the **widget**
shows *to a visitor* — including the widget's own system translations for the Calendar module and the
file uploader. An operator's own app language and a tenant's widget language can legitimately differ,
and must never be presented as, or implemented as, the same toggle anywhere. Worth a short note
wherever the two settings' backing values are eventually read in real code, since a future reader could
reasonably guess they are the same thing given the name overlap in casual conversation ("язык").

## The actual open question

Is English support worth building at all right now, given `project_commercial_intent`'s own framing
of this app as a launch aimed at Russian-speaking clients in the near term, not a portfolio-breadth
exercise? Three honest options, costs stated plainly rather than picked for the author:

1. **Build it now.** Full string audit + translation + `AppCompatDelegate` wiring + an actual Язык row
   in Settings. Real, multi-day effort, and every future string added to the app from this point on
   owes a second translation to stay in sync — an ongoing tax, not a one-time cost.
2. **Defer it, keep the Язык row out of Settings entirely** (what `26-77` ships) until there is an
   actual second language to offer — consistent with this project's own "a row exists only for a
   screen/feature that exists" rule already applied to `MoreScreen`'s own Автоматизация/
   Администрирование.
3. **Something narrower** — e.g. English only for a specific, small surface (an onboarding/sign-in
   screen a non-Russian-reading evaluator might see first) rather than the whole app. Not explored in
   any depth here; named only so it isn't forgotten as a possibility.

## Done when

Not applicable — this item is closed as `not planned` if the author decides English support is not a
near-term priority, or rewritten with a real Scope/Done-when once a direction is chosen. No code
changes are scoped here.
