# a tenant can export one person's data without exporting everybody's

- **Stage**: 24
- **Status**: ready
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

- [ ] A conversation-scoped export exists and contains that conversation and nothing else — asserted
      by a test that seeds a second conversation and proves it is absent.
- [ ] A visitor-scoped export exists for a channel-identified visitor, spanning their conversations.
- [ ] What each scope includes, and what it deliberately excludes, is written down where a tenant can
      read it — not only in the code.

## Open questions

- **Do operator notes go in?** They are personal data *about* the visitor written by someone else, and
  `18-04` made them structurally unreachable from visitor-facing paths on purpose. Including them in a
  subject-access export is defensible and so is excluding them; it is a decision, and it belongs to the
  author with a lawyer, not to the implementer.
