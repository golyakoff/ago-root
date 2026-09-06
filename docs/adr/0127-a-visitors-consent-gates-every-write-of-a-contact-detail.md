# ADR-0127: a visitor's consent gates every write of a contact detail, on both entry points, and the tenant publishes their own consent text through 24-02's existing document mechanism

- **Status**: Accepted
- **Date**: 2026-09-06
- **Stage**: 24 (`24-05`)

## Context

`24-05` needs a per-site, off-by-default gate: where a tenant turns it on, a visitor's own recorded
consent (`24-01`'s `AcceptanceRecord`) must exist before this system accepts a contact detail from
them, and refusing must never touch the conversation itself. Two things the backlog item names but
does not settle, because they were not yet decided when it was written:

`23-09` (a visitor's own contact-capture form) and `23-10` (an operator promoting a phone already
typed in the transcript) both end in the same call — `RecordVisitorContactDetailHandler`, one class,
two entry points (`HandleAsVisitorAsync`/`HandleAsOperatorAsync`). The item's own "Depends on" line
names both as "the acts this consent actually attaches to," without saying whether the gate should
sit behind one entry point or both.

Separately, `24-02` built exactly one mechanism for a document's versioned text —
`Document`/`PublishedDocumentVersion`, published only through `POST /api/v1/owner/documents`, gated
by `RequirePlatformOwner` — deliberately for AGO's own documents, because "a document is not
tenant-scoped, it is AGO's own" (`PublishDocumentVersionHandler`'s own remarks). `24-05` needs the
opposite: a tenant's own words, in the tenant's own control, publishable by an operator holding
`site:configure` on their own site, never by AGO and never reachable across tenants.

## Decision

**The gate is checked on both entry points**, inside `RecordVisitorContactDetailHandler`, immediately
before either builds a `VisitorContactDetail` row — never earlier (nothing above it changes: opening
the panel, reading the auto-reply, sending an ordinary message are all untouched) and never inside
`Conversation` itself. A site with `WidgetConfig.RequireContactConsent` off (the default, unchanged
for every existing row) is unaffected either way. Where it is on, an operator promoting a number a
visitor already typed in the transcript (`23-10`) is gated exactly like the visitor's own form
(`23-09`): the write is what is newly making a number findable and actionable, regardless of which
side of the conversation triggers it, the identical personal-data-shape argument `23-09`'s own
backlog item already made for why a visitor-typed number sitting in `messages.body` does not exempt
its later, structured recording.

**A second document mechanism was not built.** `PublishDocumentVersionHandler` gained a second entry
point, `HandleAsSiteConsentAsync`, sharing the identical publish core (`Document.Publish`, the retry
loop, the cache eviction) with the existing owner-only `HandleAsync`. It differs only in who may call
it (`Permission.SiteConfigure`, checked inside the handler, the same permission `UpdateWidgetConfigHandler`
already checks for this exact tenant) and how the document key is obtained: `SiteConsentDocumentKey.For(siteId, purpose)`
derives it from the caller's own `SiteId` and a closed `VisitorConsentPurpose` enum (`Contact`/`Marketing`)
— never from a caller-supplied string, which is what keeps an operator from ever targeting another
tenant's key, or AGO's own, through this route. The read side is unchanged: `24-02`'s existing
unauthenticated `GET /api/v1/documents/{key}` route serves it exactly as it serves any other key.

**Any accepted version satisfies the gate, not only the current one.** `adr/0114` left "does a new
version invalidate an existing acceptance" as an open, lawyer-owned question. Until it is answered,
`RecordVisitorContactDetailHandler` treats any past acceptance under the site's own contact-consent
key as sufficient — the reading that never silently re-demands a consent nobody withdrew.

**Marketing consent rides the identical mechanism, one enum value over, and never gates anything.**
`RecordVisitorConsentHandler` (a new, visitor-only entry point — no operator twin, deliberately,
since consenting on someone else's behalf is exactly the self-service act this item forbids) records
an acceptance for `Contact` or `Marketing` against the caller's own site; only `Contact` is ever read
back by the gate.

## What the statute turned out to require, checked 2026-09-06 after this was drafted

This ADR was written before anybody had read the current text. Three rules in force since
**1 September 2025** bear on it, and the honest position is that **two of them this design already
satisfies and the third it does not answer**:

- **Pre-ticked boxes are prohibited.** Satisfied: both checkboxes are created unticked and nothing
  sets `checked` or `defaultChecked` anywhere in the widget.
- **Several purposes may not be combined in one consent.** Satisfied, and by accident of the reasoning
  above rather than by knowledge of the rule: the contact consent and the marketing consent are
  separate controls, and the marketing one is deliberately not `required`.
- **Consent must be a separate document, not bundled into another agreement.** **Not answered here.**
  What this design gives is a tick against a named, versioned document the tenant publishes. Whether
  that satisfies *«отдельный документ»* is a determination about form, and an engineer reading an
  amended statute is exactly the wrong person to make it. It is filed as `25-02`'s line **D7** rather
  than assumed either way.

Recording this rather than quietly re-writing the ADR to sound prescient: the design was reasoned from
the product question and turned out to line up with two of three formal rules. That is luck worth
naming, because the third one is still open.

## Consequences

**Positive.** The gate is one small, testable surface (`ConsentSatisfiedAsync`, one method) rather
than logic smeared across two handlers or into `Conversation`. A tenant needing this control gets a
mechanism identical in shape to the one they already use for the widget's processing notice — set a
flag, publish their own text — with no new concept for an operator to learn. Reusing `24-02`'s
document store means a superseded consent text is still readable later, for free, the same guarantee
`24-02` already gives AGO's own documents.

**Negative, named rather than hidden.** Gating the operator's own promote path (`23-10`) is a real
product cost this ADR accepts deliberately: a tenant who turns on `RequireContactConsent` will find
an operator unable to promote a number a visitor typed in chat until that visitor separately accepts
— and this codebase, as of this item, has no operator-facing way to *ask* for that consent mid-conversation;
the console screen that would do so is out of this item's scope. A site should not turn the flag on
expecting `23-10` to keep working exactly as before. Second: because any past acceptance satisfies the
gate regardless of version, a materially rewritten consent document does not force re-acceptance — if
the eventual legal answer requires it, `ConsentSatisfiedAsync`'s version check is the one line to
change, not a rebuild. Third: `documents`/`published_document_versions` now hold two shapes of content
under one table — AGO's own governed text and a tenant's own words — distinguished only by key
convention (`site-consent-*`), not by a column; a future reader must not assume every row there was
reviewed the way an owner-published one was.

## Alternatives considered

- **Gate only the visitor's own form (`23-09`), leave `23-10` alone.** The reading that matches Jivo's
  own shape most literally (their checkbox sits on the contact form specifically). Rejected: the
  backlog item's own "Depends on" line names both acts together, and the personal-data argument
  `23-09` already made for structuring a visitor-typed number applies identically regardless of which
  side of the conversation performs the write.
- **A second, parallel document store scoped to sites from the start**, rather than extending `24-02`'s
  owner-only one. Rejected as premature generalisation: the underlying mechanics (versioned, immutable,
  server-minted version ids) are identical either way, and `24-02`'s own type never assumed
  tenant-scoping was impossible — only that nothing needed it yet. Two stores with one shape would be
  the failure `clean-architecture.md`'s qualifying rule warns against.
- **A caller-supplied document key on the tenant's publish route**, gated only by the caller already
  holding `site:configure` *somewhere*. Rejected outright: `24-02`'s document namespace is flat and
  global by design, so a caller-chosen key would let one tenant's operator overwrite another tenant's
  consent text, or AGO's own, the moment their permission check passed for their own site.
- **Requiring the current version specifically, not any past acceptance.** Rejected for now, the same
  reason `adr/0114` itself declined to decide it: inventing a re-acceptance requirement nobody has
  asked for costs a real conversion price (a returning visitor asked to accept again) for a legal
  question that has not been answered either way.
