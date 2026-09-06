# two ADRs were outside their own index, and nothing looked

- **Stage**: 24
- **Status**: done (2026-09-06)
- **Depends on**: nothing
- **Decision**: none — this is a missing check, not a choice

## Goal

An ADR that exists can be found by somebody reading the decisions as a set.

## What was actually true, found 2026-09-06

`docs/adr/0036` (Keycloak on a separate database inside the shared Postgres) and `docs/adr/0037` (the
capacity release absorbs the assignment engine's deadlock) **had no row in `docs/adr/README.md`**. Both
are `Accepted`, both are cited by other documents, and neither could be found by anyone browsing the
index. The table jumps from `0034` straight to `0040`.

The index is the only place these decisions can be read as a set, so an ADR missing from it is a
decision that exists and cannot be discovered.

## Why the gap is structural rather than careless

`land-a-slice` §5 forbids two open pull requests touching `docs/adr/README.md` at once, because they
collide on the same region of the same table every time. The correct behaviour under that rule is for a
second concurrent ADR to ship **without** its index row and for somebody to add it in the change that
lands next.

That is a rule whose compliance depends on remembering. On 2026-09-06 three ADRs were in flight at once
(`0123`, `0124`, `0125`), each correctly omitting its row — which is exactly the situation that produced
`0036` and `0037` some months earlier.

## What was done

- `tools/queue-audit.sh` gained a check: every `docs/adr/NNNN-*.md` must have a row in the index.
- The rows for `0036` and `0037` were written.

Two things the check deliberately does **not** do:

- **It does not flag a row with no file.** `0052` and `0062` are vacant on purpose — reserved numbers
  for items that turned out to need no decision, kept unreused so a reference to them is a mistake
  rather than a different decision. The index says so in the row itself.
- **It does not fail the run.** Like every other check in that script it reports, because a check that
  goes red trains people to make it green rather than to read it.

## Outcome (2026-09-06)

Proven the way a check should be: it flagged `0036` and `0037` against the tree that lacked their rows,
and reports *Every ADR file has a row* against the tree that has them.

One bug in the check itself, found by running it rather than by reading it: the first version read
`primary_root` — the whole-repository root every other check in that script uses — and so reported a
missing row that the very edit adding it had just written, one directory away. The other checks ask
"what does the repository as a whole know"; this one asks "is the change in front of me complete", and
those are different questions about different trees.
