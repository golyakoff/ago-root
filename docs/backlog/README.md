# Backlog

One file per unit of work: `<stage>-<nn>-<slug>.md`, e.g. `0-03-arch-tests.md`. A backlog item is
sized to one feature branch and one MR. If it cannot be, it is two items.

The point of this folder is that a session with no memory of any previous session can pick up a file
and do the work correctly. If a file does not contain enough to make that true, it is not ready.

## Format

```markdown
# <title>

- **Stage**: <roadmap stage>
- **Status**: ready | blocked | in progress | done
- **Depends on**: <other backlog files, or "nothing">
- **Verified**: <date>, <what was checked against the real code> — see "Verify before ready" below

## Goal
One paragraph: what exists after this is done, in terms of behaviour, not files.

## Context to read first
The docs, ADRs and skills that constrain this work.

## Scope
Bullet list of what to build.

## Out of scope
What a session might reasonably add and must not, with the reason.

## Done when
Checkable statements. Tests that must exist and pass. Docs that must be updated.

## Open questions
Anything needing the author's decision. If any is unanswered, status is `blocked`.
```

## Rules

- **Status is updated in the file**, never tracked only in someone's head.
- Scope creep discovered mid-work becomes a new backlog file, not a bigger branch.
- An item with an unanswered open question does not get started; ask the author instead.
- Items are written by `/stage`, by the author, or by any session that discovers real work — but
  never silently expanded once written.

## Verify before ready

**"No open questions" is not the same claim as "verified."** An item can list zero open questions
and still be wrong about what it's asking for — its premise unconfirmed against the real code, a
dependency it needs quietly missing, or the exact feature it wants already shipped under a different
name. `queue-audit.sh` computes the ready queue from the `Status` line alone; it has no way to tell
"nobody has checked this yet" from "this was checked and holds up" — so it is on whoever files or
picks up an item to make that distinction visible, not silent.

**A freshly filed item is `ready — **not yet verified against the real code**`, not plain `ready`.**
`tools/queue-audit.sh` already treats any `Status` starting with `ready` but continuing past it as
QUALIFIED rather than READY — this reuses that existing mechanism rather than inventing a new one.
Before flipping the qualifier off (to plain `ready`), actually check the claim:

- **For a bug**: read the code path the report describes and confirm the described symptom is what
  it actually does — don't take a reporter's own diagnosis as the mechanism until it's read against
  the source. `25-35`'s own two named candidate causes were both wrong; the real one was found only
  by tracing the code.
- **For a feature or enhancement**: search for an existing implementation **by concept, not by the
  item's own wording** — the thing asked for may already exist under a different name. `25-59` asked
  for a tag-filtering mechanism; investigation found the tags themselves, and every mechanism but the
  one filter, already shipped.
- **For anything with a `Depends on` list**: confirm each dependency actually delivers what *this*
  item needs, not just that it's `Status: done`. `25-23` depended on nothing by its own first draft;
  reading the actual handler it would need found a real, missing dependency (`25-41`) nobody had
  written down.

Once the check holds up, remove the qualifier and record what was checked on the `Verified` line.
If it doesn't hold up, the item's own `Depends on`, `Scope`, or premise gets corrected before the
qualifier comes off — never silently, the same "found while checking" honesty this folder already
expects for a Done-when box.

## Choosing the number

**Look in this folder, not only at the board.** A number is free when no file here starts with it
*and* no issue's title does. The board shows issues; a planned item that has a file and no issue is
invisible there, so its number reads as available.

That is not hypothetical: eight numbers ended up naming two items each, six of them this shape
(`22-21`). `NN-NN ·` is the only thing tying an issue to its file, its stage, its ADRs and its
commits, so a number used twice makes every one of those links ambiguous — and the collision surfaces
much later, when one side ships and the other still says `ready`.

```bash
cd C:/git/ago/ago-root && ls docs/backlog/ | grep '^<stage>-'
```

`tools/queue-audit.sh` catches it afterwards. Checking first is cheaper: once both sides have shipped,
the number cannot be reclaimed from either.
