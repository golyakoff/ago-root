# twenty-one files set state in an effect, and the rule is only a warning there

- **Stage**: 23
- **Status**: done
- **Depends on**: `23-96`, which turned the rule on and bounded what it found.
- **Found**: 2026-09-08, when `eslint-plugin-react-hooks` v7 first ran over this console.

## What is true

`23-96` migrated the plugin to v7, whose `recommended-latest` carries seventeen rules where v5 carried
two. One of the new ones, `react-hooks/set-state-in-effect`, fired **thirty times**. Seven were pure
state resets and were rewritten with React's own adjust-state-during-render technique. **Twenty-three
remain, across twenty-one files**, and the rule is downgraded to `warn` for exactly those files.

They are two shapes, and the split matters because the fixes differ:

- **reset-on-id-change** — a panel clearing its own state when the conversation or worker it is showing
  changes;
- **fetch-on-mount** — a screen loading a default window of data the first time it renders.

`eslint.config.js` carries the file list.

## Why it is a real item and not bookkeeping

**The downgrade is per-file, not per-line.** ESLint has no mechanism to distinguish a finding that
existed when `23-96` landed from one written tomorrow, so **a new `set-state-in-effect` in any of those
twenty-one files is also only a warning**, and `npm run lint` will not fail on it. `23-96`'s first draft
claimed otherwise and was corrected at landing.

So this is not "tidy up some warnings". It is: twenty-one files are currently outside a gate the rest of
the console is inside, and the list is the only thing keeping that bounded.

## Why it was not done inside `23-96`

Because the fixes are per-screen judgements, not a mechanical rewrite. Moving a fetch out of an effect
changes *when* a request is made, and getting that wrong is a screen that loads twice, or not at all, in
a way tests that mount once will not notice. Twenty-three of those inside a lint-migration diff would
have been unreviewable.

## Scope

- **Convert the remaining twenty-three**, taking the two shapes separately — the reset shape is
  mechanical once the pattern is agreed; the fetch shape needs a decision per screen about when the
  request should happen.
- **Delete the override block** when the list empties. Leaving an empty list behind is how the next
  person concludes the exception still applies to something.

## Where this is likely to go wrong

- **A test that mounts a screen once cannot see a double fetch.** Whatever proves these needs to
  exercise a change of the thing the effect depends on, not just an initial render.
- **`useLayoutEffect` is not the answer here.** It was the right move for the ref-mirror findings
  `23-96` fixed; for a fetch it only makes the request block paint.
- **Do not widen the override instead of shrinking it.** If a file is genuinely unfixable today, it
  stays on the list with a reason of its own — the failure would be adding files to buy a green run.

## Done when

- [x] The override block is **deleted**. Eight findings were converted outright; the remaining
      fifteen carry a per-line disable with its own reason naming what that screen loads, not one
      boilerplate repeated fifteen times.
- [x] `react-hooks/set-state-in-effect` is a full error across the console - proven by adding a
      synchronous `setState` in an effect to `CalendarQueuePage`, one of the twenty-one formerly
      exempt files, and watching it fail as an error where the override made it a warning.
- [x] The proof exercises a dependency change. `renderSync` is built on `flushSync` rather than
      `act()` precisely because `act()` drains the passive-effect queue even synchronously, which
      makes the old and new code indistinguishable. Each test mounts with one `conversationId`,
      re-renders with a **different** one, and asserts the previous conversation's content is gone
      *before* any effect could have run.
