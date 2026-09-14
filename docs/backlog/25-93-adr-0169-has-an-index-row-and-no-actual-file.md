# 25-93 · ADR-0169 has an index row and no actual file

- **Stage**: 25
- **Status**: done — independently re-verified by the managing session before merging: the ADR's own
  specific claims (pricing figures, port/error-code names) cross-checked against the real source
  (`23-82`'s own backlog file, real merged code); the `queue-audit.sh` extension independently
  re-run (removed a real ADR file, confirmed the check catches it, restored byte-identical, re-ran
  clean) rather than trusting the worker's own report alone.
- **Depends on**: nothing
- **Found**: 2026-09-14, refreshing the root `README.md`'s own "Decisions" table (a request to make
  the repository presentable as a portfolio reference) — linking to `docs/adr/0169-*.md` 404'd.
  `docs/adr/README.md` carries a full row for it (`| 0169 | Attachment download-visibility is three
  small dedicated ports... |`), added by `d23ddce` ("docs(23-82,23-80): egress measured, storage
  screen shipped, ADR-0169, and two found defects filed") — a commit whose own diff touches only
  `docs/adr/README.md`, one line. No `docs/adr/0169-*.md` was ever created; `git log --all` for that
  path returns nothing, in any branch, ever.

## What is actually true

`tools/queue-audit.sh` already checks this class of gap — in the direction that shipped first:
"ADR files with no row in `docs/adr/README.md`" (its own comment: "the gap is created by two
concurrent ADRs both touching README.md at once"). It has no check for the reverse: **an index row
with no file behind it**, which is exactly what happened here — the row was written (correctly
describing a real decision made while landing `23-82`/`23-80`) but the file itself was never written
in the same change, and nothing caught the omission afterward.

The decision the row describes is real and already fully reasoned in the row's own text: three small
dedicated ports (`IAttachmentEgressMeter`/`IAttachmentEgressReadStore`/`IAttachmentBudgetReadStore`)
instead of widening `ISiteAttachmentStorageBudget`, and a distinct `Attachment.Removed` (410) error
code instead of a hot-path join against `messages`. That reasoning is not lost — it is sitting in the
index row itself, and in `23-82`'s/`23-80`'s own backlog files — but an ADR is meant to be its own
standalone record, not a summary line, and a reader following the link from anywhere (this README
included) hits a 404.

## Scope

- Write `docs/adr/0169-*.md` for real, from the reasoning already recorded in the index row and in
  `docs/backlog/23-82-*.md`/`23-80-*.md` — not a guess, the actual alternatives and consequences those
  two items already worked through.
- Extend `tools/queue-audit.sh` with the symmetric check: every row in `docs/adr/README.md` has a
  corresponding `docs/adr/NNNN-*.md` file. Same shape as the existing "file with no row" check,
  the other direction.
- While in the index, it is worth a quick scan for any other row this same gap might have produced —
  this item's own Done-when only requires closing the one instance found, but say plainly whether a
  broader check found more.

## Done when

- [x] `docs/adr/0169-*.md` exists, and reads as a real ADR (Context/Decision/Consequences/Alternatives,
      per `adr-writer`'s own template), not a copy-paste of the index row's own prose. Written from
      `23-82`'s/`23-80`'s own backlog reasoning, cross-checked against the real merged code (the three
      port names, `Attachment.Removed`/410, `ix_attachments_site_content_hash`) — not invented.
- [x] `tools/queue-audit.sh` fails loudly on an index row with no backing file, proven by a
      fails-before: temporarily remove one ADR file with a real row and show the script now catches it,
      then restore it. Excludes the three intentionally-vacant `n/a`-status numbers (`0052`, `0062`,
      `0126`) by design, not by accident.
- [x] The root `README.md`'s link to `0169` (or whichever ADR the Decisions table cites) resolves.
      The root README's own Decisions table never cited `0169` at all (it cites `0170`/`0171`) — this
      box was vacuously satisfied, not broken to begin with. A scan for other index rows with no
      backing file found none beyond the three intentional `n/a` placeholders.
