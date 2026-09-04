# a contact is the tenant's asset: it is in the register, it has its own clock, and erasure reaches it

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §4, the *a contact is the tenant's asset* correction
  (2026-09-04)

## Goal

`visitor_contact_details` becomes a store this system can account for: it appears in the personal-data
register, its retention is stated (indefinite, because it is the tenant's asset), and a person's
erasure request reaches it. Today none of those three is true, and the third is a real gap rather
than a documentation one.

## What is actually wrong today, verified

- **The register does not mention it.** `personal-data.md` inventories every store this system holds
  and `visitor_contact_details` is not among them. §4's own words: *"indefinite retention of personal
  data the register does not mention is its own problem, and not a UX one."* The table holds a phone
  number or an email address as structured, exact text — the same class as AGO Calendar's
  `customers`, which the register calls "the most directly identifying store either product has".
- **Erasure does not reach it.** `16-02`'s `ConversationErasureQuery` deletes messages, attachments,
  notes, tags and the conversation row. `visitor_contact_details` has a foreign key to **`visitors`**,
  not to `conversations`, so a conversation erasure leaves the phone number behind. Site erasure
  cascades and is unaffected.
- **The clock was never written down.** The ninety days proposed while §4 was being decided were
  never agreed and are wrong.

## The two clocks, which nobody may later collapse into one

§4's correction, stated here because it is the whole reason the item exists:

- **The contact** ends when the person asks for erasure, or when the tenant judges it useless. It has
  no timer.
- **The transcript** runs to the end of the contract, under `adr/0031`/`13-06`'s per-tier window.

**Erasure paths diverge accordingly.** A person's erasure request takes the conversation **and** the
contact — it is all their data. Sweeping old conversations by retention takes only the transcript, or
the tenant would lose an asset every time a transcript aged out. *There is a link; there is no
cascade.*

## Context to read first

- `docs/design/decisions.md` §4 in full, including the *what this dissolves* paragraph
- `docs/architecture/personal-data.md` — the table's own shape, and the standing rule that a change
  which adds a personal-data store is not a small change
- `docs/adr/0031-*` and `docs/backlog/13-06-*` — the transcript's clock, which this item does not
  touch and must not appear to
- `docs/backlog/16-02-erasure-account-and-conversation.md`;
  `Ago.Chat.Application/UseCases/RequestConversationErasure/RequestConversationErasureHandler.cs`
  (whose own remarks describe it as "a tenant deletes one visitor's conversation **on that visitor's
  request**" — which is exactly the person's-erasure case §4 names) and
  `Ago.Chat.Worker/ConversationErasureQuery.cs`
- `Ago.Chat.Domain/VisitorContactDetail.cs`'s own remarks on why it is deliberately not a
  `ChannelIdentity`

## Scope

- **`personal-data.md` gains the `visitor_contact_details` row**: what is held (a phone number, an
  email address, or a short annotation an operator typed), control, **how long — indefinitely, as the
  tenant's asset**, what removes it, and where the fact was verified. It also gains the two-clocks
  sentence, in the retention section, beside the transcript's own window.
- **Erasure reaches it.** `ConversationErasureJob` / `ConversationErasureQuery` gains a step that
  deletes the erased conversation's **visitor's** contact details, drained explicitly rather than
  left to a cascade, so the deletion is observable in the job's own count — the same treatment
  `DeleteNotesForConversationAsync` and `DeleteTagsForConversationAsync` already get.
  **State the scope decision in the code**: the contact belongs to the visitor and the request is the
  visitor's, so it goes; a second conversation of the same visitor is a second request and is
  untouched by this one.
- **No cascade from retention.** Assert it: the message-partition prune and the archive gate remove
  message rows and leave every contact standing. This is true today by construction and the test
  exists so a future retention job cannot quietly change it.
- **The tenant's own action already exists and is named as such.**
  `DELETE /api/v1/conversations/{conversationId}/contact-details/{id}`
  (`DeleteVisitorContactDetailHandler`, gated on `Permission.ConversationSend`) and the console's
  visitor aside (`ui-inventory.md` §3.4, panel 7) already give a person a per-row Delete. This item
  builds no new action; it records in `personal-data.md` that this is the removal path, so §4's
  sentence about the tenant needing an action to say so is met by something that exists rather than
  by a plan.

## Out of scope

- The visitor-supplied write path, the source flag and the unverified mark — `23-09`, which changes
  this table's shape. This item deliberately lands first, so a register entry and an erasure path
  exist *before* the store gains a second kind of row.
- Changing the transcript's retention, or making it depend on this.
- Masking. That is `23-11`.
- A visitor-scoped erasure endpoint. The conversation-scoped one already carries the visitor's
  request; inventing a second entry point is a wider change than §4 asked for.

## Done when

- [ ] `personal-data.md` carries the row, the indefinite retention, and the two clocks stated as two.
- [ ] Erasing a conversation removes that visitor's contact details, asserted, and the erasure job's
      own count includes them.
- [ ] Erasing a conversation does **not** remove another visitor's contact details.
- [ ] A retention sweep of messages removes no contact detail — an integration test, because this is
      the property the decision is most afraid of losing.
- [ ] Deleting a site still cascades them, unchanged.

## Open questions

None.
