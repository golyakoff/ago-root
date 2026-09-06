# the launch compliance checklist, kept until the first real tenant

- **Stage**: 25
- **Status**: in progress — the file exists and is maintained; it closes when its own lines close
- **Depends on**: `25-01` for section A, which no amount of writing can close from here
- **Decision**: the author's, 2026-09-06 — *"нам надо сделать какой-то чеклист и вести его до запуска,
  чтобы не лажануть и не всхлопотать штраф в первые дни"*

**Written retrospectively, 2026-09-06.** `docs/compliance-checklist.md` shipped in `7a19e75` and was
corrected against the statutory text in `5518e08`, but this item file was never written — so the queue
carried an open issue whose deliverable had already landed twice, with nothing recording what it was
for or when it may be closed. `tools/queue-audit.sh` found it. The file below is what should have been
written first.

## Goal

Before the first paying tenant, every obligation under `152-ФЗ` is either **closed with an artefact
somebody can point at**, or visibly open with a named owner — so nothing is discovered at the moment
it is being enforced.

## Why a file rather than a conversation

The failure this guards against is not ignorance of the law. It is **confident memory of it**. The
checklist was drafted from recollection and then checked against sources; the corrections that pass
made are the most valuable content in it, and they are marked where they happened rather than quietly
folded in. Two examples of what memory got wrong: art. 22's notification exemptions were repealed on
1 September 2022, and the consent *form* rules changed again on 1 September 2025 — a separate document,
no combined purposes, no pre-ticked boxes.

**The author's instruction on this was explicit and is the reason the file is trustworthy at all:**
*"не надо на память — проверяй закон в Интернет"*. Every statutory claim in the file was checked
against a source on 2026-09-06, and the sources are listed in it.

## The shape, and the one rule that makes it a checklist

Eight sections — where the data physically sits, telling the regulator, what we publish, consent, the
person's own rights, protection level and its measures, when something goes wrong, and being somebody
else's processor.

**A line is ticked only when somebody can point at the artefact.** Not *"we do that"* — here is the
document, here is the test, here is the screen. Every line also carries who can close it:

| Mark | Meaning |
|---|---|
| **built** | The mechanism exists in this codebase and something proves it |
| **document** | Needs a document written, signed or obtained — not code |
| **lawyer** | Needs a lawyer's determination; an engineer's reading is not enough |
| **provider** | Needs a paper from whoever hosts the machine |

That last distinction is the point of the whole exercise. A **lawyer** line closed by an engineer
reading a statute is not closed, it is guessed — and this project would have guessed several of them
before the checklist existed.

## What it already changed

- **`25-01` exists because of section A.** Fornex does not issue the documents a processor needs, so
  the deployment has to move. That was found by trying to tick a line, not by planning.
- **`25-04` exists because of H4.** The AI switch is AGO's, deployment-wide — a processor adding a
  processing purpose and a sub-processor on its own initiative is precisely what a processing
  instruction exists to constrain.

## Scope

- The file itself, kept current as items close — it is a living document, not a one-off audit.
- A protection level determined and recorded (**УЗ-4** under ПП-1119, on the author's own reading that
  no financial or medical data is held), with the measures that level requires listed rather than
  assumed.
- Every line owned: nothing marked *"probably fine"*.

## Out of scope

- **Legal advice.** The file says so in its own closing section, and the **lawyer** marks exist so that
  the boundary is visible line by line rather than in a disclaimer nobody reads.
- Closing the lines themselves. Each is its own work, and several are their own items already.

## Done when

- [x] The file exists, with all eight sections and a mark on every line.
- [x] Every statutory claim in it was checked against a source, and the sources are listed with the
      date they were checked.
- [ ] No line is left without a named owner.
- [ ] Every **built** line points at the test or screen that proves it.
- [ ] The **lawyer** lines have been through a lawyer.
- [ ] The **provider** lines have the papers — which needs `25-01` first.
- [ ] Nothing is red at the moment the first real tenant signs up.
