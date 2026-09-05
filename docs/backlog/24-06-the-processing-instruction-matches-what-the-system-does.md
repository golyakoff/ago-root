# the processing instruction says what the system actually does, item by item

- **Stage**: 24
- **Status**: done (2026-09-05), `ago-root#481`. Delivered
  `docs/architecture/processing-instruction-facts.md`; the eight gaps it found are `24-07`..`24-14`.
- **Depends on**: nothing in this stage. It can be done first if the tenant agreement is being drafted.
- **Decision**: `docs/adr/0076-*` — AGO processes visitors' conversation data **on the tenant's
  instruction**

## Goal

The clause in the tenant agreement that instructs AGO to process their visitors' data describes the
system that actually exists — each required element answered from the register rather than from
memory.

## Why this is an engineering item and not a legal one

The text belongs to `ago-business` and a lawyer, and this item does not write it. But `152-ФЗ`
art. 6 ч. 3 requires the instruction to state specific things, and **every one of them is a fact about
the system that only this repository knows**:

| The instruction must state | Where the answer already lives |
|---|---|
| the list of personal data | `personal-data.md`'s table — that is what it is for |
| the list of actions performed on it | the stores plus the jobs that touch them |
| the purposes of processing | per store, and some of them are not obvious |
| the duty of confidentiality | `secrets.md`, `authorization.md` |
| the localisation requirement (art. 18 ч. 5) | where the database physically runs |
| the obligation to produce evidence on request | what we could actually produce today |
| security measures (art. 19) | `edge.md`, `secrets.md`, the isolation guards |

A lawyer drafting from a description of the system rather than from the system produces a clause that
is wrong in the direction nobody checks. This item is the bridge: it produces the answers, sourced and
dated, so the drafting starts from facts.

Citations are for orientation, not legal advice.

## What is actually true today, verified

- `adr/0076` records the controller/processor split, and `personal-data.md` says plainly that the
  processing clause in the tenant agreement is an open `ago-business` item.
- `personal-data.md` already holds the register, the retention windows, and a "What is unestablished"
  section — this item's output is largely an assembly of it, plus the gaps that assembly reveals.

## Scope

- One document in `ago-root` answering each required element with a reference to where in the codebase
  or the architecture docs the answer comes from, and the date it was checked.
- **Gaps are named as gaps.** Where the honest answer is "we could not produce that today", that is the
  finding, and it is worth more than a confident sentence. The localisation question in particular has a
  physical answer that should be stated rather than assumed.
- A note in `personal-data.md` pointing at it, so the register and the instruction do not drift.

## Out of scope

- The agreement's text, its negotiation, and the regulator notification. `ago-business` and a lawyer.
- Fixing whatever gaps this turns up. Each becomes its own item — that is what makes this one able to
  finish.

## Done when

- [x] Every element required by art. 6 ч. 3 has an answer or a stated gap, each with its source.
- [x] `personal-data.md` links to it.
- [x] Every gap found has a number of its own, rather than a paragraph promising to look later.

## Open questions

- **Where the data physically sits** is the element most likely to produce a real finding rather than a
  citation, and it is the one this repository can answer precisely. It should be answered early, because
  the answer could change more than a document.
