# a context file exports a hook, so Fast Refresh cannot work on it

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `23-96` is its sibling from the same batch and is a different kind of problem.
- **Found**: 2026-09-07, by a **patch** release of a lint plugin.

## What is true

`src/i18n/StringsContext.tsx` exports `StringsProvider` and the `useStrings` hook from the same file.
`eslint-plugin-react-refresh` 0.5.6 flags it:

> Fast refresh only works when a file only exports components. Use a new file to share constants or
> functions between components.

**This is a finding about our own code, not a plugin regression.** The rule is right: a file mixing a
component export with a non-component export defeats Fast Refresh for that module, so editing the
console's strings context reloads more than it should during development.

`golyakoff/ago-console#146` is the Dependabot pull request, left open rather than closed so the bump
lands with the fix.

## The seam this item named was the wrong one — corrected 2026-09-08 at landing

This item said to move `useStrings` out. **That does not satisfy the rule**, and it was established by
trying it rather than by reading: with the hook elsewhere, the raw context has to be exported beside the
Provider so the hook can reach it, and the rule fires again with a different message — *"Move your React
context(s) to a separate file."* A component export and a raw context export cannot share a file either.

**The working split is the reverse: the Provider moves out alone**, and the context object and the hook
stay together, neither being a component. That is also what `AuthContext` and `OperatorConnectionContext`
already do here, their own doc comments citing this same Fast Refresh reason — so the codebase had the
answer and this item did not consult it.

## Why this is worth a number rather than a line inside the batch

The original reasoning was that **every import moves with the hook** — a diff across many files whose
only visible justification inside a dependency batch would be a patch version number.

**That reasoning was wrong along with the seam.** Seventy files import `useStrings` and none of them
move; two import `StringsProvider` and both change. The item is still worth its own number — a source
refactor riding a patch bump is unreviewable regardless of size, and the *investigation* of which seam
works is the substance — but not for the reason given.

## The thing worth remembering from how this was found

**A patch release changed what is checked.** `0.5.5 → 0.5.6` — the smallest bump there is — started
flagging code that had been passing. So the version number was not a guide to the risk, and "patches
can be merged in a batch, majors need a look" is a rule of thumb this case breaks.

The batch that carried it (`golyakoff/ago-console#155`) held three of seven back, and **none of the
three was held because a test went red**: one broke ESLint entirely, one found this, and one was a
lock-only change. Reading each was what separated them.

## Scope

- **Move `useStrings` out of `StringsContext.tsx`**, update every import, and take the 0.5.6 bump in the
  same change so the rule that found it is what proves it fixed.
- **Check the neighbours.** If one context file mixes exports, others plausibly do; the rule will say so
  once it is running.

## Where this is likely to go wrong

- **Do not silence the rule.** A `// eslint-disable` here buys nothing — the Fast Refresh cost is real
  and is paid by whoever develops the console, quietly, every time they edit that file.
- **The provider and the context object are not the same thing.** `StringsContext` itself is a
  `createContext` result, not a component; check what the rule actually wants exported before splitting
  along the wrong seam.

## Done when

- [x] `^0.5.6` is in, and lint is clean without a suppression: **294 files, 0 errors, 0 warnings**,
      measured 2026-09-08. The fix is a split, not a silence - `StringsProvider` moved out of
      `StringsContext.tsx`, the same shape `AuthContext` and `OperatorConnectionContext` already use.
- [x] Established: every other `createContext` call site was checked - `AuthContext`,
      `PermissionsContext` and `OperatorConnectionContext` - and all three already have this shape,
      so there is no remainder to carry out. Worth recording that the item's own prescription (move
      the *hook* out) does not work: with the hook elsewhere the raw context has to be exported beside
      the Provider and the rule fires again with a different message.
