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
