# the machine answers a visitor by itself

- **Stage**: 23
- **Status**: ready — **and it is the largest product question in the automation ladder**
- **Depends on**: `25-04` (the add-on), `23-38` (the draft's own screen and its precedent)
- **Decision**: **open on every axis below.** Nothing about this is settled

## Goal

A tenant who wants it can let the machine answer a visitor without an operator in the loop.

## What is actually true today

**Nothing of this exists.** `19-01` drafts a reply *for an operator to send*; `19-02` categorises a
*closed* conversation. Both keep a person between the machine and the visitor. `14-04`'s offline
auto-reply answers without a person, but from a **fixed text the tenant wrote** — a rule, not a model.

So the automation ladder `23-31` draws — готовые ответы → ИИ-подсказки → автоответ → ИИ-автоответ —
has its top rung missing, and it is missing for a reason rather than by oversight.

## Why this is the hard one

Every rung below it keeps a person answerable for the words. This one does not.

- **A wrong answer is the tenant's word to their customer**, said in their name, with nobody having
  read it. That is a different product from everything above, and the tenant has to understand it is
  what they bought.
- **When does it stop?** Handing over to a human on doubt is the whole design, and "doubt" has to mean
  something checkable — not a model's own confidence, which is not evidence.
- **What can it promise?** A machine that quotes a price, a date, or an availability is making a
  commitment somebody must honour. The calendar makes that concrete: `23-35` has not decided whether a
  service even has a price.
- **The visitor's own consent.** `25-04` records that the tenant declares a basis for conversation
  text reaching the vendor. An answer *generated* for the visitor is a further step, and whether it
  needs its own basis is a lawyer's question, not ours.

## Scope, once the questions are answered

Deliberately not written. An item that specified this before the decisions below would be specifying
one of several products.

## Out of scope

- The reply draft and its screen — `23-38`.
- The rule-based offline auto-reply — `14-04`, which already ships and stays.

## Done when

- [ ] The author has answered the four questions below, and they are written down.
- [ ] Whatever was decided is built — or this is closed as not-planned with the reasoning kept, which
      is a perfectly good outcome for a rung that may not be worth climbing.

## Open questions

1. **Does a human ever see it before the visitor does?** If yes this is a slower draft, not an
   auto-reply. If no, everything below matters.
2. **What makes it stop and fetch a person**, in terms somebody can check afterwards.
3. **May it state a fact — a price, a slot, an availability** — or only converse?
4. **Whose consent does a generated answer need**, beyond the tenant's declaration in `25-04`.
