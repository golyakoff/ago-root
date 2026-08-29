# ADR-0076: AGO is controller for its own accounts, processor for a tenant's visitor data - and the widget carries the tenant's notice

- **Status**: Accepted
- **Date**: 2026-08-29
- **Stage**: 16 (`backlog/16-04-widget-processing-notice.md`)
- **Related**: `docs/architecture/personal-data.md` ("Who answers to whom" - the working direction this
  ADR turns into a decision; "What is not decided here" - the legal questions this ADR does not
  answer), `backlog/16-02-tenant-initiated-erasure.md`, `backlog/16-03-tenant-data-export.md`
  (product requirements this split explains rather than merely motivates), `adr/0029` (the widget-config
  precedent this item's own two fields extend - fixed, named, validated fields, read at bootstrap)

## Context

Two different kinds of person hold data in this system, and they got here two different ways.

**Operators and tenants** (an AGO account holder - the person or shop that registered, signed the
onboarding form, and holds a Keycloak identity) chose to have a relationship with AGO directly. AGO
decided why their account data is processed (running the product they signed up for) and how (this
system's own architecture). That is the textbook shape of a data controller: the party that decides
the purpose and means of processing.

**A visitor** (the person typing into a shop's embedded chat widget) never had that choice. They are
the *tenant's* customer, arrived on the *tenant's* page, and is talking to the *tenant's* support
team. The tenant decided to run a support chat at all, and picked AGO to build and host the software
that carries the conversation. AGO stores the messages, routes them, and can act on them - but AGO
did not decide that this conversation should exist, what it is for, or how long the tenant's own
relationship with this customer should be honoured. That is the textbook shape of a data processor
acting on a controller's (the tenant's) instruction.

This split is not new information - `docs/architecture/personal-data.md` has stated it as a "working
direction, to be confirmed by the lawyer" since `16-01`'s own inventory pass, precisely because two
things already built only make sense if it is true:

- **`16-02`/`16-03`** (tenant-initiated erasure and export) are built as product requirements a tenant
  can invoke on their own conversations, not as an AGO-operated courtesy a support ticket might
  eventually honour. That shape is only correct if the tenant is the one who owes their visitor an
  answer under a "right to erasure"/"right to access" - which is to say, only if the tenant is the
  controller of that data and AGO is carrying out the instruction.
- **The widget needs to say something to a visitor before they type**, and it has to be the tenant's
  own sentence, not AGO's - `16-04`'s own Goal. If AGO were the controller of visitor conversation
  data, AGO's own published policy (on `ago-landing`, in `ago-business`) would already cover it, and
  no per-tenant notice mechanism would be needed at all. The fact that a per-tenant notice is required
  is itself evidence for which side of the split this data sits on.

**What this ADR does not have**: a lawyer's signature. `docs/architecture/personal-data.md`'s own
"What is not decided here" section is explicit that "whether AGO is controller or processor for which
dataset" is a legal question belonging to `ago-business` and a lawyer, not to this repository. This
ADR is the engineering side's own commitment - the shape every product decision since `16-01` has
already assumed, written down as a decision instead of implied by the code - not a substitute for that
legal confirmation. If the confirmation comes back different, this ADR is superseded, not quietly
edited; see Consequences.

## Decision

**AGO is the controller for its own account holders' data** (operators, tenants - anyone who
registered with AGO directly, per `10-02`/`15-*`'s own onboarding and account-management flows). AGO
decides why and how that data is processed, and answers for it directly.

**AGO is a processor, acting on the tenant's instruction, for a visitor's conversation data.** The
tenant is the controller: they decided to run a support chat, they decide what their notice says, and
they are who a visitor's own data-subject rights (erasure, access) are owed to. AGO's job is to build
and run the mechanism the tenant's instruction requires - store the conversation, route it, and expose
the two tools (`16-02` erasure, `16-03` export) a controller needs to honour a request without asking
an engineer to run a manual query.

**The widget carries a processing notice - text and a link - supplied entirely by the tenant.**
Concretely, this item adds `NoticeText`/`NoticeUrl` to `Ago.Chat.Domain.WidgetConfig` (a third and
fourth field alongside `adr/0029`'s primary color and launcher position - the same fixed, named,
validated shape, not a new mechanism), editable in the console's existing widget-config screen,
delivered on the same handshake response the widget already fetches at bootstrap. Both are nullable
and independent; the default for every site, including every site that predates this column, is
`null` on both - the widget renders nothing. **AGO never authors a default notice.** A generic
AGO-written sentence would be AGO asserting a legal position (what the tenant does with visitor data,
and how) on the tenant's behalf, which contradicts the processor role this ADR just assigned AGO: a
processor does not decide what the controller tells their own customers.

**The notice text is rendered as text, escaped, never HTML**, and the link is validated `https://`
only (the scheme-only reflex `6-03`'s webhook URL validator applies, without that validator's
SSRF/private-range check - a notice link is only ever handed to the visitor's own browser as an
`<a href target="_blank" rel="noopener noreferrer">`, never fetched by any AGO server, so the SSRF
threat model that check exists for does not apply here). This is `adr/0029`'s own "arbitrary
injection" refusal, applied to a field that looks harmless because it is prose rather than CSS: a
tenant-supplied string rendered inside a shadow tree the widget's own script controls is a security
boundary question independent of what kind of string it is.

## Consequences

- **`docs/architecture/personal-data.md`'s "Who answers to whom" section now points at this ADR**
  instead of describing a direction, per this item's own Done-when. The "working direction, to be
  confirmed by the lawyer" sentence is replaced with a pointer here; the confirmation itself is still
  pending and still belongs to `ago-business`.
- **A tenant who leaves both notice fields empty gets no notice, silently.** This is a real, accepted
  gap this ADR does not paper over: if the (still pending) legal answer turns out to require a notice
  unconditionally, every tenant who has not configured one is out of compliance the day that answer
  lands, through no fault of the mechanism - the mechanism was always optional by design, because
  mandating tenant speech is not AGO's call to make either. Whoever resolves the open legal question
  is the one who would need to decide whether "optional" becomes "required, with a fallback", and that
  is a new, scoped item, not a silent tightening here.
- **A consent gate - blocking the chat until the visitor clicks something - is explicitly out of
  scope**, named in `16-04`'s own Scope and not decided by this ADR. Whether a notice is legally
  sufficient, or whether affirmative consent must be collected, is exactly the open legal question;
  building a gate now would be answering it by default rather than waiting for the answer.
- **AGO's own account-holder data (operators, tenants) is unaffected** - this ADR does not change how
  AGO handles that side, only names it as the controller relationship it already was.
- **If the lawyer's answer contradicts this split** (for example, if AGO turns out to be a joint
  controller, or if a different allocation applies to a specific dataset this file's inventory has not
  yet separated out), this ADR is superseded by a new one, not edited - `adr-writer`'s own rule, and
  the reason the record has any value at all once a real answer exists to compare it against.

## Alternatives considered

- **AGO as controller for visitor conversation data too** - rejected on the facts, not on preference:
  AGO does not decide why a given shop's support chat exists or what happens to a given visitor's
  data once the tenant relationship ends; the tenant does. Treating AGO as controller here would also
  make `16-02`/`16-03` read as AGO's own courtesy features rather than what they actually are - tools
  that let a controller (the tenant) honour an obligation that is legally theirs, not AGO's.
- **No per-tenant notice at all - rely on AGO's own published policy** (`ago-business`, on
  `ago-landing`) to cover the whole platform. Rejected: that policy is AGO's own statement as a
  controller/processor of the platform, not the tenant's statement about their own use of the
  visitor's data, and conflating the two is exactly the shape a processor-not-controller relationship
  forbids - AGO cannot describe what a tenant does with their own customer's data on the tenant's
  behalf without the tenant saying so.
- **A default notice, written by AGO, shown unless a tenant overrides it** - rejected, stated
  explicitly in the backlog item's own Scope and restated here because it is the alternative most
  likely to be proposed later by someone optimising for "every widget shows something": AGO authoring
  the sentence is AGO deciding what the tenant tells their own customer, which is the controller's
  decision to make, not the processor's.
- **Waiting for the lawyer's confirmation before building anything** - rejected per the backlog item's
  own framing: the mechanism (a field, storage, an API, a rendering path) is identical regardless of
  which specific legal answer eventually lands, the same way `16-02`/`16-03` did not wait for a
  finalised privacy policy before building erasure/export. What would change with a different legal
  answer is *whether the field is used and how it is worded*, not whether the field exists.
- **A consent gate built alongside the notice, "just in case" the lawyer requires one** - rejected as
  premature generalisation: a gate has a real conversion cost `16-04`'s own Scope names explicitly,
  and building it speculatively ahead of the actual legal requirement is exactly the failure mode
  `clean-architecture.md`'s qualifying rule warns against for a platform-level feature, applied here to
  a product-level one.
