# a visitor can leave a name and a phone, and it is stored as a contact

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-08` — the register entry and the erasure path, which must exist before this
  store gains a second kind of row
- **Decision**: `docs/design/decisions.md` §4, including its 2026-09-04 correction

## Goal

A visitor who arrives when nobody is there can leave a name and a way to be reached, and that contact
is stored as a contact — findable, erasable on request, and marked unverified. `flows.md` 1.2's
success condition out of hours is not *answered*, it is **contact kept**.

`RecordVisitorContactDetail` exists and its route sits behind `"RequireOperatorIdentity"`
(`ContactDetailEndpoints`), so today a visitor cannot write one at all.

## The framing that settles "should we accept a visitor's number"

§4, and it belongs in the item: the phone **already arrives**, as free text in a message. People type
"call me on +7…" today, and that is personal data too — sitting in the conversation body where nobody
can find it and nobody can act on it. The question is not whether to accept visitor-supplied numbers
but whether to accept them in a shape that can be worked with. Structured is a *reduction* of risk.

§4's correction sharpens this and removes a worry an earlier draft of this item was blocked on: the
structured contact is **not** a way to keep the number out of messages. The transcript is already
personal data of the same class — a clothing size, an illness mentioned before a booking, an address
— so erasure works on the transcript wholesale rather than hunting for substrings. The contact exists
to make the number **findable and actionable**. A number that also appears in a message body is not a
defect of this design.

## The shape chosen, and why

The control is **widget-native**: a form rendered by the widget, submitted to a visitor-authenticated
endpoint. It is deliberately **not** an `adr/0065` primitive:

- `adr/0065` §4 closes the primitive vocabulary at four kinds; a fifth is an amendment to that ADR,
  and this item does not need one.
- `form` is **one field per message** today, so name plus phone would be two messages.
- Producing a structured payload would make Chat a *producer* of module content for the first time,
  against `adr/0065` §1's premise that Chat never opens one.

The alternative — riding §8's "compose a message and send it into the conversation" mechanism — was
considered and rejected on those three grounds, not on the personal-data grounds the correction
dissolved. Say so in the ADR below, because the rejected option is the one a later reader will
propose again.

## Context to read first

- `docs/design/decisions.md` §4 **and** §8
- `docs/design/flows.md` 1.2 (including the author's own suggestions block and the interest note) and
  1.4's failure branch
- `docs/adr/0079-*` section 6 and `Ago.Chat.Domain/VisitorContactDetail.cs`'s own remarks on why it
  is deliberately not a `ChannelIdentity` — that reasoning is what an unverified flag protects
- `docs/adr/0065-*` §1 and §4; `ago-widget/src/ui/primitives/render.ts`
- `docs/architecture/tenant-isolation.md` — the visitor-token scheme, and
  `Ago.Chat.Api/Auth/AuthEndpoints.cs`'s renewal route as the existing `JwtSchemes.Visitor` precedent
- `docs/backlog/14-04-offline-auto-reply.md`, `adr/0066`
- `.claude/skills/embeddable-widget/SKILL.md`

## Scope

- `VisitorContactDetail` gains a **source** (`Operator` | `Visitor`) and a **verified** flag, and
  `recorded_by_operator_id` becomes nullable — a visitor-supplied detail has no operator behind it.
  One additive migration on `visitor_contact_details`.
- **Unverified is marked unverified.** §4's reason: one flag now, against a booking flow six months
  from now reading a contact from the profile and treating it as an identity nobody checked.
- **A visitor-authenticated write path** — a handler beside `RecordVisitorContactDetailHandler`,
  reached under `JwtSchemes.Visitor`, scoped to the visitor's own conversation, resolving the visitor
  from the validated principal's `sub` and **never** from a conversation id the caller merely names.
  Rate-limited like every other public write.
- **The control**, in the widget: name and phone, one reusable component with two modes — with
  verification and without — and **the control does not decide which**. Its first and only caller
  here is the out-of-hours path (`SendOfflineAutoReplyHandler`, `14-04`).
- **No verification for a callback.** §4's principle: verification is paid for by whoever benefits.
  In booking the visitor benefits — the code protects *their* slot. For a callback only the tenant
  benefits, and the cost of a fake number is one wasted call. Making the visitor prove their identity
  for somebody else's benefit is how you lose them at the last step.
- **Consent is a requirement, not a UX detail**: the visitor is told what the number will be used for
  before they give it, in the widget's existing processing notice, whose text the tenant owns
  (`adr/0076`, `16-04`) and which AGO never authors.
- `personal-data.md`'s row (added by `23-08`) is amended to record the new source and the unverified
  mark.
- **An ADR** (number to be assigned). §4: the stated meaning of a contact detail changes and must
  change loudly. Today it is documented as "recorded by an operator — never used to contact the
  visitor automatically" (`ui-inventory.md` §3.4, the panel's own caption); a visitor-supplied
  callback number is the opposite. Not a silent reuse of a field with its meaning reversed.

## Out of scope

- The verified mode's own caller. Booking already verifies (`14-15`, `20-09`); wiring the control
  into that flow is a separate change and would drag `20-10`'s widget question in with it.
- The "everyone is busy, call me back" case during working hours, and the abandoned conversation.
  §4 names them as users of the same control; each is its own moment with its own trigger.
- Promoting a number out of message text — `23-10`, a different actor and a different act.
- Masking. Chat's contact details are read under `Permission.ConversationRead`; the ladder is
  `23-11`, and this item must not quietly invent a second, differently-shaped one.
- A retention window. `23-08` settles it: indefinite, as the tenant's asset.

## Done when

- [ ] Out of hours, a visitor is offered the control, fills it in, and a row exists in
      `visitor_contact_details` with source `Visitor` and unverified.
- [ ] The visitor cannot write a contact detail onto a conversation that is not theirs — a
      tenant-isolation test in the shape `tenant-isolation.md`'s visitor-token rows already use.
- [ ] A visitor cannot set the verified flag, by any request they can construct.
- [ ] The operator's visitor aside distinguishes an operator-recorded detail from a visitor-supplied
      one, and says which are unverified.
- [ ] Erasing the conversation removes it (`23-08`'s path, asserted again from this source).
- [ ] The processing notice is shown before the field, and the tenant's own text is what is rendered.
- [ ] `personal-data.md` carries the amended row; the ADR exists and supersedes the old caption's
      claim; `ui-inventory.md` §3.4's caption is corrected.

## Open questions

None. The question an earlier draft carried — whether the control rides `adr/0065`'s primitive
vocabulary — is answered above, and the answer is the conservative one: it does not, and that ADR is
unamended.
