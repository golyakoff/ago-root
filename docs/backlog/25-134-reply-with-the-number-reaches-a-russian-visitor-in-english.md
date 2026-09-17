# 25-134 · "Reply with the number." reaches a Russian visitor in English

- **Stage**: 25
- **Status**: done — `ago-chat#323` (bundled with `25-135`, same file)
- **Found**: 2026-09-17, live, reported by the author: a Russian-language booking response ends with
  an English instruction line.
- **Depends on**: none. Touches `ago-chat` only. Shares files with `25-135` - land in the same lane,
  same worker, sequentially (two commits/PRs, one worktree).

## The gap

`Ago.Chat.Domain.PrimitiveTextRenderer.Render` (`ago-chat/src/Ago.Chat.Domain/
PrimitiveTextRenderer.cs`) builds the plain-text rendering of a choice-shaped step - the prompt, the
numbered list, and a trailing instruction line, hardcoded at line 57:

```csharp
sb.Append("\nReply with the number.");
```

`Render` takes **no locale parameter at all**. Every other string this same conversation shows a
Russian visitor already comes from `ModuleStepFactory`'s locale-aware `Strings` table (`25-37`) -
this one line is Chat's own, not Calendar's, and `25-37`'s scope never reached it because `25-37` was
scoped to `ModuleStepFactory` specifically. `RouteConversationToModuleHandler.FinishStepAsync`
(`ago-chat/src/Ago.Chat.Application/UseCases/RouteConversationToModule/
RouteConversationToModuleHandler.cs:439-440`) already resolves the site's own `Locale` for this exact
call (it threads it to `ModuleStepFactory` via the module wire contract) - the value exists at the
call site; `Render` just never receives it.

A second, related hardcoded-English string in the same handler, found while tracing this: `"Done -
thank you."` (`RouteConversationToModuleHandler.cs:397`), the system message added when a module
finishes with no further step. Currently unreachable in practice (`ago-calendar` always returns a
confirmation step, so this branch never fires against the shipped booking module) but latent, and
the same `25-66` locale-threading pass that covered `ModuleEscalatedFallbackText` missed it. Fixed in
the same change since it's the same mechanism and the same file.

## Scope

- Add a `Locale` (or `string locale`, matching whatever `ModuleStepFactory.Strings.For` already
  accepts) parameter to `PrimitiveTextRenderer.Render`, and give the trailing instruction line an
  English/Russian pair the same "closed set of two, hand-written" shape `ModuleStepFactory.Strings`
  already uses - this is Chat's own primitive vocabulary, so the strings belong in
  `Ago.Chat.Domain`, not borrowed from Calendar's table.
- Thread the resolved locale into **both** call sites: `RouteConversationToModuleHandler.
  FinishStepAsync` (already has it) and `DeliverChannelMessageHandler` (`ago-chat/src/
  Ago.Chat.Application/UseCases/DeliverChannelMessage/DeliverChannelMessageHandler.cs:171-174`,
  which does not resolve a site's locale today - it will need a `Site` read, the same shape
  `RouteConversationToModuleHandler`'s own `ResolveModuleContextAsync` already uses).
- Localize `"Done - thank you."` the same way, in the same file.

## Where this is likely to go wrong

- Do not touch anything in `ago-calendar` - the locale plumbing this item needs already exists
  end-to-end; this is purely a Chat-side gap.
- An unrecognised/unset locale must still render English - the same safe-default posture
  `ModuleStepFactory.Strings.For` already takes, not a throw.
- This item and `25-135` both touch `PrimitiveTextRenderer.cs`. Land whichever lands second on top of
  the first, not as two parallel diffs to the same file (the same instruction `25-38` gave itself
  against `25-37`).

## Done when

- [x] A Russian-locale site's Telegram/MAX visitor (and, until `25-133` lands, a widget visitor too)
      sees the instruction line in Russian
- [x] `RouteConversationToModuleHandler`'s own fallback "Done - thank you." message is localized the
      same way
- [x] An unset/unrecognised locale still renders English
- [x] Widget behaviour is otherwise unaffected - after `25-133` lands, the widget never shows this
      text at all, but this item does not depend on `25-133`

## Outcome

Landed bundled with `25-135` in one PR (`ago-chat#323`) - both touch `PrimitiveTextRenderer.cs`, the
same reasoning `25-37`/`25-38`/`25-39` already used. A new `PrimitiveTextRenderer.Strings`
English/Russian table (mirroring `Ago.Calendar`'s own shape) covers both the instruction line and
`RouteConversationToModuleHandler`'s "Done - thank you." fallback; `Render` gained a `string? locale`
parameter threaded through both call sites. Verified independently: full suite green (Domain 737,
Application 1371, FakeCrm 21, Architecture 49, Concurrency 89, Integration 1320).
