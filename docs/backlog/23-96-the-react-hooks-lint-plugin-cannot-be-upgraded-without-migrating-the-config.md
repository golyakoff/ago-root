# the react-hooks lint plugin cannot be upgraded without migrating the config

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing.
- **Found**: 2026-09-07, while combining the console's Dependabot pull requests.

## What happens

`eslint-plugin-react-hooks` 5.2.0 → 7.1.1 **does not fail a rule — it stops ESLint from running at all**:

> A config object has a "plugins" key defined as an array of strings.

The config the plugin exports at v7 uses the legacy `plugins: [...]` array shape, and ESLint 9's flat
config refuses it. `npm run lint` exits without linting anything.

`golyakoff/ago-console#145` is the Dependabot pull request, deliberately left open rather than closed,
so that whoever picks this up has the upstream diff to hand.

## Why it was held out of the dependency batch

**Because migrating that config decides which lint rules run, and a green CI afterwards cannot tell
"the rules pass" from "the rules stopped running".**

That is the same failure this project has already met twice in one day, in two unrelated places: a
drift check that printed `PASS` because it normalised away the only drift that happens (`23-90`), and a
widget test that passed by phase coincidence whether or not the behaviour it named was bounded
(`23-63`). A check that has quietly stopped checking looks exactly like a check that passes.

So the acceptance for this item is not "lint is green afterwards". It is **the same rules, or a stated
difference**.

## Scope

- **Migrate the flat config to v7's shape**, whatever that turns out to be — read the plugin's own
  release notes rather than inferring from the error.
- **Establish what changed in the rule set**, and write it down. v7 is two majors on from v5; rules
  will have been added, removed or renamed, and `react-hooks` is the plugin most likely to have opinions
  about code that currently passes.
- **Whatever it newly flags is either fixed or explicitly deferred with a reason.** Not silenced.

## Where this is likely to go wrong

- **A migration that lints fewer files is the failure, not the fix.** Record the file count before and
  after — on 2026-09-07 the console had `eslint src` reaching **265 files**, which is the number to
  compare against.
- **`eslint-plugin-react-refresh` is a separate item** (`23-97`) even though both surfaced in the same
  batch: one is a config migration, the other is a real defect in our own code, and they land green
  independently.
- **`ago-calendar-console#21`** is an open issue about `@eslint/js@10` against `eslint@9` making
  `npm install` unresolvable — a different repository and a different package, but the same family of
  problem, and worth reading before assuming this one is isolated.

## Done when

- [ ] `npm run lint` runs, on v7, over no fewer files than before — the number recorded, not assumed.
- [ ] What the rule set gained or lost between v5 and v7 is written down.
- [ ] Anything newly flagged is fixed, or deferred with its own reason.
