# an erasure can be proven afterwards

- **Stage**: 24
- **Status**: ready
- **Depends on**: `16-02` (shipped — the erasure this must become provable)
- **Decision**: `personal-data.md`, "Deletion versus backups" — a deletion **journal** was deliberately
  rejected, and this item must not reintroduce one

## Goal

Asked months later whether a named person's data was destroyed, and when, this system can answer with
something other than "the rows are not there".

## What is actually true today, verified 2026-09-05 (`24-06`)

`ConversationErasureJob` deletes the MinIO objects, the messages in batches, the notes, the tags, the
visitor's contact details (`23-08`) and the row, and leaves **no durable record that any of it
happened**. `SiteErasureJob` is the same. The only trace is a log line, and container logs are kept 14
days (`adr/0057`). `conversations.erasure_requested_at` is on the row being deleted, so it goes with it.

`export_requests` is the contrast worth noticing: `16-03` kept a metadata row per export — id,
requester, status, object key, timestamps, no personal content — precisely so an export is a thing that
can be shown to have happened. Erasure has no equivalent.

## Why this is a gap rather than an oversight

`personal-data.md` rejected a deletion journal on good grounds — "the journal is itself a list of people
who asked to be forgotten, which is a worse thing to hold than the short window it removes" — and that
reasoning is correct and stays correct. What it never separated is **a journal from a receipt**. A
journal identifies the person; a receipt need not: what was erased at what scope, on whose request,
when, how many rows and objects went, and whether every step completed.

That distinction had no reason to be drawn until somebody asked what evidence this system could
produce, which is `24-06`. The rejection was of the wrong artifact, and it took the right one with it.

## Scope

- A durable erasure record, holding no identifier of the erased person: scope, requesting operator,
  timestamps, per-step counts, completion or failure.
- The same shape `export_requests` already has, for the same reason — this is deliberately the
  precedent rather than a new mechanism.
- Its own row in `personal-data.md`, including what it does **not** hold and why.
- The backup window stated alongside it: `adr/0050`'s 30 days is when the erasure is complete in full,
  and a receipt that implies "gone now" would be the dishonest version of this item.

## Out of scope

- Anything that names or re-identifies the erased person. That is the rejected journal, and this item
  fails if it produces one.
- The formal act-of-destruction document, if one is required. That is `ago-business` and a lawyer;
  what this item supplies is the fact the document would be drawn from.

## Done when

- [ ] Every erasure — conversation and site — writes a record that survives the erasure.
- [ ] The record contains no identifier of the person erased, asserted by a test, because that is the
      one property that makes this item safe to build at all.
- [ ] `personal-data.md` has a row for it.
- [ ] `processing-instruction-facts.md` Element 6 moves this line out of "could not be produced".

## Open questions

- **How long does a receipt live?** Long enough to answer a question that arrives late, which argues
  for longer than anything else in `adr/0057`. It carries no personal data of the erased person, which
  makes that affordable — but it does carry the operator's id, so it is not free either.
