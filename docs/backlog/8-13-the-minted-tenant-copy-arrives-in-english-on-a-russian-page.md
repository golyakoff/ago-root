# A minted tenant's page copy arrives in English, on a page written in Russian

- **Stage**: 8
- **Status**: done — `ago-widget#102`
- **Depends on**: nothing.

## What is wrong

`8-11` made the demo pages' honesty copy follow the *tenant* rather than the page: on a tenant minted
from the button, `demo-boot.js` swaps two sentences so a visitor on their own private tenant is not
told a stranger can read what they type. That mechanism is right and is not in question here.

The replacement strings it swaps in are **English**, and both demo pages are **Russian**
(`public-demo/index.html`, `public-demo-2/index.html`, `<html lang="ru">`).

`src/demo/boot.ts`, `applyOwnTenantPageCopy`:

```ts
swap(doc, "ago-demo-public-notice",
  "You are on a tenant of your own. The operator login published below belongs to the shared demo "
  + "shops, not to this tenant - nobody but you can read what you type here. …");
swap(doc, "ago-demo-privacy-note",
  "Safe for the deployment, and private for you on this page: …");
```

So a visitor who presses «Получить свой тенант» watches the warning strip at the top of a Russian
storefront turn into an English paragraph, and the safety note at the bottom do the same. The page
around them stays Russian.

Two reasons this is worth a number rather than a note:

- **It lands on the reassuring sentence.** The swapped copy is the one that says "nobody but you can
  read this". A visitor who cannot read it is left with a warning they can no longer parse, on the
  one screen where the honest state of their own privacy is the whole point (`8-06`'s reason for
  existing).
- **It is the one place in this repository where display text is written in a `.ts` file at all.**
  Every other visitor-facing string in the widget goes through `src/i18n/ru.ts` / `en.ts` and
  `resolve.ts`. These two sentences bypass that entirely, which is both why they are untranslated and
  why nobody noticed.

Found 2026-09-18 while redesigning `public-demo/index.html`; not caused by that change — the strings
have read this way since `8-11`.

## Done when

- [x] The two swapped sentences come from the widget's own string table (`WidgetStrings`, both locales),
      resolved the same way every other visitor-facing string is, rather than being literals in
      `boot.ts`.
- [x] A minted tenant's page reads in the same language as the page it replaced text on, verified on both
      demo pages rather than only in a unit test.
- [x] `boot.test.ts` covers the Russian resolution as well as the English one, so a future locale cannot
      regress it silently.

## Outcome

New `resolveDemoPageLocale(doc)` reads the page's own `<html lang>` - the one locale signal available
this early (before `session.widgetLocale` exists). Both sentences moved into `WidgetStrings`
(`demoOwnTenantBannerNotice`/`demoOwnTenantPrivacyNote`). **Correction to this item's own premise**:
`public-demo-2/index.html` is actually `lang="en"`, not Russian as originally stated - only
`public-demo` is Russian; the fix resolves per-page regardless, so this doesn't change the outcome.
Verified live in a browser against both real demo pages, not only via `boot.test.ts` (which also gained
the Russian-resolution coverage). 453/453 tests green (+5). `ago-widget#102`.

## Considered and not chosen

- **Translating the two literals into Russian in place.** Cheaper, and wrong in the same way: the
  pages are Russian today because the market is (`ago-business/decisions/0002`), and the widget
  itself already resolves a locale per visitor. Hardcoding the other language swaps which visitor is
  stranded rather than fixing anything.
- **Leaving it because the pages are demos.** The demo is the first thing a prospective customer
  touches, and this is the sentence that tells them whether their conversation is private.
