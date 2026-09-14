# 25-66 · Three more hardcoded-English system messages in chat routing

- **Stage**: 25
- **Status**: done — `ago-chat#287`.
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

- [x] All three texts render in Russian on a `Locale.Ru` site, English otherwise, proven by a test per
      text (the same fails-before pattern `25-64`'s own phone-text tests use).
- [x] `dotnet format`/build/full suite stay clean.

## Outcome

Shipped as `ago-chat#287`. Built by a background worker, independently re-verified by the managing
session (its own `dotnet build`/`test` run against the worker's own worktree — 3292/3292 tests,
matching the worker's reported counts exactly) and merged.

Exactly the Scope section, no more: `ModuleUnavailableText`/`ModuleBecameUnreachableText`/
`ModuleEscalatedFallbackText` each became a `static string Method(string locale)`, identical shape to
`PhoneVerificationRequiredText`. `locale` is threaded from the one resolution
`ResolveModuleContextAsync` already does per call in `ContinueActiveTaskAsync` - no new read - but that
resolution's own call site moved earlier in the method (ahead of the `enabledModule is null` check, not
only ahead of the phone gate) so `ModuleBecameUnreachableText` could reach it for that branch too; the
worker's own report has the full before/after. `ModuleEscalatedFallbackText` is reached from
`FinishStepAsync`, the one method both `TryStartTaskAsync` and `ContinueActiveTaskAsync` share, so it
gained a `locale` parameter threaded from both call sites rather than being resolved a second time.

Four new tests in `RouteConversationToModuleHandlerTests.cs` (`Ago.Chat.Application.Tests`), one per
call site actually reachable (`ModuleUnavailableText` at trigger time, `ModuleBecameUnreachableText` at
both its own call sites - the module-disabled-mid-task branch and the module-unreachable-mid-reply
branch - and `ModuleEscalatedFallbackText`), each on a `Locale.Ru` site, asserting the Russian wording
appears and the English original does not. `dotnet format --verify-no-changes` clean, full solution
`dotnet build -c Release` clean (0 warnings), full `dotnet test -c Release` run for the whole `ago-chat`
solution - the worker's own report has the exact per-assembly pass counts.
