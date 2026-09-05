# a tenant can export one person's data without exporting everybody's

- **Stage**: 24
- **Status**: done (2026-09-05). Two granularities beside `16-03`'s whole-site export, synchronous, with `adr/0109` for why. Documentation landed later the same day — see the Outcome.
- **Depends on**: `16-03` (shipped — the export machinery this narrows)
- **Decision**: `docs/adr/0076-*` — the tenant owes their visitor the answer; AGO supplies the tool

## Goal

A tenant honouring one visitor's access request can produce that visitor's data, and only that
visitor's.

## What is actually true today, verified 2026-09-05 (`24-06`)

Export has exactly one granularity: `POST /api/v1/sites/{siteId}/exports`. `SiteExportJob` writes one
`.zip` per tenant per export holding conversations, messages, attachments by presigned URL, operators,
visitors, channel identities and site configuration — the whole site, as of the moment it ran
(`SiteExportArchiveWriter`, `adr/0072`).

Erasure, by contrast, has two: `POST /api/v1/conversations/{conversationId}/erase` and
`POST /api/v1/sites/{siteId}/erase`.

So a tenant asked for one person's data must export every person they hold and extract by hand — which
is not merely inconvenient. It puts every other visitor's transcript into an artifact created to answer
one person's request, on the tenant's own laptop, for as long as it sits there. The safe answer and the
easy answer point in opposite directions, which is how it gets done unsafely.

## Why this is a gap rather than an oversight

`16-03`'s own framing is tenant **portability** — a tenant taking their data with them, for which
whole-site is exactly right. Subject access is a different question that happens to want the same
machinery at a different scope, and the two were never put side by side. `16-02` had the same choice
and landed on both scopes because deletion makes the difference obvious: nobody would ship
"delete my data" as a site-wide button. Export's asymmetry is quieter.

## Scope

- Export at the granularity erasure already has: one conversation, and — where a visitor is
  channel-identified and therefore has more than one — that visitor.
- Reuse `16-03`'s format and its artifact handling rather than inventing a second export shape; the
  presigned-link expiry (`adr/0072`) and its stated limitation apply unchanged.
- The same permission thinking the erasure endpoints already use, not a new one.
- What a visitor-scoped export includes is stated explicitly, because it is a judgement, not a join:
  the transcripts, the contact details (`14-14`), the channel identity — and **not** an operator's
  private note about them (`18-04`) unless that is deliberately decided.

## Out of scope

- Letting a **visitor** request it directly. The tenant is the controller (`adr/0076`); the visitor
  asks them, not AGO. A visitor-facing request flow is its own item and its own product decision.
- Pruning the export archives, which nothing does today.

## Done when

- [x] A conversation-scoped export exists and contains that conversation and nothing else —
      `POST /api/v1/conversations/{conversationId}/exports` (`ExportConversationHandler`), asserted by
      `PersonExportIntegrationTests.ExportingAConversation_ProducesAnArchive_ContainingOnlyThatConversation_NotASecondOne`,
      which seeds a second conversation on a different visitor and proves its message bodies, channel
      address and contact detail are all absent. Shown failing without the writer's own
      `conversation_id = any(@conversationIds)` predicate (fails-before proof, not merged into the
      writer).
- [x] A visitor-scoped export exists, spanning every conversation the same visitor has —
      `POST /api/v1/conversations/{conversationId}/visitor-export` (`ExportVisitorHandler`), asserted by
      `PersonExportIntegrationTests.ExportingAVisitor_ProducesAnArchive_SpanningAllTheirConversations_ButNotAnotherVisitors`.
      **Not gated on a channel identity** (`adr/0109`'s own reasoning: that gate answers a different
      question, and a widget-only visitor can already hold more than one conversation under the same
      row).
- [x] What each scope includes, and what it deliberately excludes, is written down where a tenant can
      read it: `manifest.json`'s own `stores`/`excludedStores` fields, inside the archive itself, plus
      `adr/0109` and this file. Operator notes and the tenant's own operator roster are excluded (see
      Open questions below and `adr/0109`'s own Decision section for the full list and each reason).

## Implementation notes (2026-09-05)

- Synchronous, not through `16-03`'s `export_requests` job queue — no new column, no migration
  (`23-06`'s own migration held this session's one slot). Both reasons are independent and both are
  recorded in `adr/0109`, not only the scheduling one.
- A new permission, `conversation:export`, distinct from `site:export` — the same granularity split
  `conversation:erase`/`site:erase` already draws.
- A new port, `IPersonExportArchiveWriter` (`Ago.Chat.Application.Abstractions`), implemented by
  `PersonExportArchiveWriter` in `Ago.Chat.Infrastructure.Postgres` — a second, smaller writer next to
  `SiteExportArchiveWriter` (which lives in `Ago.Chat.Worker` and stays untouched), agreeing on the
  same wire format (`adr/0109`'s own reasoning for why this is not that class widened with a filter).
- Found, not fixed: `SiteExportArchiveWriter` (the whole-site export) never writes
  `visitor_contact_details` at all — `14-14` shipped after `16-03` merged. Left for its own ticket;
  `adr/0109`'s Consequences section records it.

## Open questions

- **Do operator notes go in?** They are personal data *about* the visitor written by someone else, and
  `18-04` made them structurally unreachable from visitor-facing paths on purpose. Including them in a
  subject-access export is defensible and so is excluding them; it is a decision, and it belongs to the
  author with a lawyer, not to the implementer. **Decided here as excluded** (`adr/0109`), on the
  argument that a subject-access export is exactly the kind of visitor-facing path `18-04` already
  keeps notes out of — reversible if the author and a lawyer decide otherwise.

## Outcome

**The asymmetry was quiet, which is why it survived.** `16-02`'s erasure shipped two granularities —
a whole account and one conversation — because deletion makes the question obvious: nobody would ship
*delete my data* as a site-wide-only button. Export had the identical choice and landed on one, and
nothing complained, because a tenant honouring an access request could always export everything and
extract by hand. That workaround **is itself a disclosure problem**, not merely an inconvenience, and
naming it that way is what turned a nice-to-have into a gap.

**The limit travels with the closure, and it is the part worth reading.** This promises completeness
for one `visitors` row. It does **not** promise that two `visitors` rows are the same human — nothing
in this schema makes that link. A tenant who assumed otherwise would under-answer a real access request
and never know. `adr/0109` says so, `processing-instruction-facts.md` says so, and neither leaves it to
be discovered.

**Synchronous, not a queued job.** `16-03`'s `export_requests` row and its worker exist because a
tenant's whole archive is large and slow. One person's data is neither, and making a subject-access
response wait on a timer would be a worse answer to a request that is, by law, time-bound.

**Deliberately not gated on a channel identity.** That gate answers a different question — *can we
reach this person* — and using it here would silently exclude a visitor who only ever used the widget.

**The documentation half and `adr/0109` sat written and uncommitted for a day.** Found by
`queue-audit.sh`'s worktree check, one of five items in that state. The ADR's absence is why the index
had a gap at `0109` that I misread this morning as a number held by unfinished work; it was held by
finished work whose record had not arrived.

**And the recovered patch did not apply cleanly**, which is the useful detail: `processing-instruction-facts.md`
had moved on — `24-12` rewrote the same section hours earlier. The Element 6 change was re-made against
the current text rather than forced. Moving a diff across bases is not the same as moving a true
statement, and this is the second time today that mattered.
