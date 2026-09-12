# 25-66 · Three more hardcoded-English system messages in chat routing

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-12, while landing `25-64` - the same class
  (`Ago.Chat.Application.UseCases.RouteConversationToModule.RouteConversationToModuleHandler`) that
  `PhoneVerificationRequiredText` lived on carries three siblings with the identical gap, deliberately
  left out of that item's own scope (CLAUDE.md rule 15 - `25-64` was one promise, "the phone-refusal
  gate honors `AcceptUnverifiedPhone`," not "every string in this class is localized").

## What is actually true

`RouteConversationToModuleHandler` renders a visitor-facing sentence for four situations. `25-37`
localized the class's `Locale`-aware paths generally; `25-64` localized the one text actually caught by
a live report (`PhoneVerificationRequiredText`, reworded to take a `locale` parameter). The other three
are still `private const string` fields, hardcoded English, regardless of the site's own configured
language:

- `ModuleUnavailableText`
- `ModuleBecameUnreachableText`
- `ModuleEscalatedFallbackText`

Each renders as an ordinary System message a Russian-configured tenant's visitor can see mid-conversation,
identical in kind to the bug `25-64` fixed for the phone-verification text.

## Scope

- Give each of the three the same shape `PhoneVerificationRequiredText` now has: a `static string
  Method(string locale)` returning the Russian wording for `nameof(Locale.Ru)` and the existing English
  text otherwise.
- Thread `locale` (already resolved once per call by `ResolveModuleContextAsync` in the caller) to each
  call site - no new resolution, no new read.
- A short, natural Russian translation for each - not a literal machine rendering.

## Out of scope

- Any other hardcoded-English text elsewhere in `Ago.Chat.*` or `Ago.Calendar.*` - this item is scoped
  to the three named siblings in this one class, found by direct inspection while landing `25-64`, not
  a general audit.

## Done when

- [ ] All three texts render in Russian on a `Locale.Ru` site, English otherwise, proven by a test per
      text (the same fails-before pattern `25-64`'s own phone-text tests use).
- [ ] `dotnet format`/build/full suite stay clean.
