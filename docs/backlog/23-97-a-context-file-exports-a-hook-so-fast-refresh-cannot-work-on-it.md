# a context file exports a hook, so Fast Refresh cannot work on it

- **Stage**: 23
- **Status**: ready
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

## Why this is worth a number rather than a one-line fix inside the batch

Because the fix is a refactor, not a version bump: the hook moves to its own file and **every import
moves with it**. That is a diff across many files whose only visible justification, if it rode inside a
dependency batch, would be a patch version number in `package.json`. Nobody reviewing that would know
what they were looking at.

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

- [ ] `eslint-plugin-react-refresh` 0.5.6 is in, and `npm run lint` is clean without a suppression.
- [ ] Whether other files share the shape is established and written down.
