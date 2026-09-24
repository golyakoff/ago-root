# 26-91 · Every user-facing string lives in resources, in Russian and English

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-23 as `26-79`, split in two on the author's own instruction 2026-09-24: this item
  is the first, quick half — moving what already exists into place and translating it. `26-92` is the
  second half — an actual Settings row and a real switch. **This item alone does not add a language
  switch anywhere** — it is the prerequisite that makes one buildable later.
- **Verified against real code, 2026-09-24**: `app/src/main/res` has exactly one resource directory
  (`values/`), holding **210** `<string name=...>` entries, all Russian. A grep across every `.kt` file
  under `app/src/main/kotlin` for a Cyrillic literal three characters or longer finds **8 files**, most
  of whose matches are `@Preview`-only sample data (visible only in Android Studio, never to an
  operator) rather than real user-facing text — read each hit before moving it; a preview's own fake
  name or business name is not translation debt.
- **Depends on**: nothing structurally, but **do not dispatch this while another lane is actively
  editing `app/src/main/res/values/strings.xml`** — the managing session's own note, 2026-09-24: `26-86`
  (a third push kind) is adding new strings to that exact file in a parallel lane as this is being
  filed. Land whichever is already in flight first; this item touches the same file wholesale and a
  rebase across two large edits to one file is real, avoidable pain.

## What this item is

One promise: **there is no hardcoded string left in any Composable, and every one of the ~210+ strings
that already live in `strings.xml` has a real English translation, not a stub.**

## Scope

1. **Extract the real, user-facing literals** — read the file list a fresh grep turns up (this item's
   own "Verified" section names the check), and for each hit, decide whether it is:
   - **A real user-facing string** — move it into `strings.xml` as a new `<string name="...">`, replace
     the call site with `stringResource(R.string.…)`, name it by what it is
     (`docs/conventions/naming-and-structure.md`-style: descriptive, not `text1`).
   - **`@Preview`-only sample data** — leave it exactly as it is. A preview's own placeholder name,
     fake business name, or demo count is dev-only content with no operator ever reading it; extracting
     it into a resource and then having to translate it would be manufacturing work nobody asked for.
     State in the report which literals were judged which way, and why, so the author can spot-check the
     judgment calls rather than trust them blindly.
2. **A real English translation for every one of the ~210 existing entries, plus whatever this item's
   own step 1 adds** — not machine-literal, not a placeholder. Where a string is genuinely ambiguous or
   this app's own domain vocabulary doesn't have an obvious settled English term (e.g. a term this
   project's own `docs/vision.md`/`plan.md` names a specific way), say so in the report rather than
   guessing silently — a wrong technical term repeated across dozens of strings is more expensive to fix
   later than one flagged question now.
3. **`values-en/strings.xml`**, the real Android resource-qualifier convention — **not** renaming or
   moving the existing `values/strings.xml` (which stays Russian, this app's own base/default language
   and the one every existing device already resolves to with zero locale configuration). Every key in
   `values/strings.xml` gets a matching key in `values-en/strings.xml`; a lint/build check that would
   catch a missing key is worth adding if this app's own tooling makes that cheap (check whether Android
   Lint's own `MissingTranslation`/`ExtraTranslation` checks are already enabled or need turning on).
4. **Record the standing rule** in `ago-android/docs/architecture.md` — the same place this app's other
   cross-cutting rules already live: **no string literal in a Composable or ViewModel from this point on;
   every user-facing string is a resource, added to both `values/strings.xml` and `values-en/strings.xml`
   in the same change.** This is what makes every future item's own brief able to say "no new literal
   strings" without re-explaining why.
5. **Format strings and plurals** (`"открыт %1$s назад"`, `"в %1$s"`, and any others the sweep finds) —
   confirm Android's own `String.format`/`stringResource(id, arg)` positional-argument handling is used
   correctly in both languages; English and Russian do not always want arguments in the same order, and
   a resource file lets each language's own translation reorder `%1$s`/`%2$s` if it genuinely needs to,
   which a hardcoded Kotlin string interpolation never could.

## Out of scope

- **Any actual runtime language switching** — `26-92`'s own job. This item ships two complete resource
  sets that nothing yet reads by locale; the app still always renders `values/` (Russian) until `26-92`
  wires `AppCompatDelegate.setApplicationLocales`.
- A Settings row, a mockup change, anything visible to an operator today. This item is invisible in the
  running app if done correctly — the English resources exist but nothing selects them yet.
- Widget-side translation (`ago-widget`/`ago-console`) — this app's own strings only; the widget's own
  language setting is a fully separate, already-existing mechanism (`26-79`'s own settled note, carried
  forward: never conflate the two).

## Done when

- [ ] Every literal the sweep judged "real, user-facing" is a resource; every literal judged
      "preview-only" is named as such in the report, for the author to spot-check.
- [ ] `values-en/strings.xml` exists with a matching key for every entry in `values/strings.xml` — no
      missing keys, no leftover keys with no Russian counterpart.
- [ ] Every English translation is a real sentence a fluent English speaker would recognize as natural
      UI copy, not a literal word-for-word rendering — spot-checked by the managing session against a
      sample, not merely asserted by whoever writes them.
- [ ] `ago-android/docs/architecture.md` states the standing "resources in both languages, no literals"
      rule.
- [ ] `./gradlew ktlintCheck lint test assembleDebug` green — Android Lint's own translation-completeness
      check, if enabled, is part of what "green" means here.
