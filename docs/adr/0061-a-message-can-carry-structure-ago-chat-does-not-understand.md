# ADR-0061: A message can carry structure AGO Chat does not understand

- **Status**: Accepted
- **Date**: 2026-08-26
- **Stage**: 14 (`backlog/14-06-structured-message-content.md`)
- **Follows from**: `reviews/2026-08-26-platform-boundary.md` — the one addition three passes of that
  review found missing
- **Related**: `adr/0027` (two products, not one), `adr/0019` (`messages` partitioning widened its
  unique index), `adr/0055` (channel identity stays AGO Chat's)

## Context

Until now a `Message` was a `MessageBody` plus an optional `AttachmentId`. Prose, or a file. That was
enough while every conversation was a human typing at another human, and it stops being enough the
moment a *product* needs to say something into a conversation.

The product model makes that unavoidable rather than hypothetical. A booking must be reachable from
the widget, from Telegram, from MAX and over SMS, and there are shops that will run with **no widget
at all**. So a booking interaction cannot be widget UI and cannot be bespoke per channel: it has to be
something the conversation itself carries.

The boundary review tested three propositions about moving the communication surface and concluded
that none of them should move. This is the single thing it found missing — and it named, in advance,
the way building it could go wrong: *"AGO Chat's message model gaining booking-shaped fields. If that
ever looks like the easy path, the boundary is being crossed and this document is the place that said
so in advance."*

## Decision

**A message may carry a kind, an opaque payload and a list of actions. AGO Chat stores, sequences,
delivers and renders all three, and interprets none of them.**

### The payload is opaque, and "opaque" is a checkable property rather than an intention

AGO Chat validates the payload's *shape* — that it parses, that it parses as a JSON object, and that
it is bounded — and never its *meaning*. It owns no schema for it and must not acquire one.

That property is enforced, not documented. `MessageOpacityTests` asserts that **no type, field,
constant, enum member, parameter or string literal in any `Ago.Chat.*` assembly names another
product's domain**, reading compiled IL rather than source text so that a comment explaining a
concept stays legal while a field named for one does not. The rule ships with a permanently violating
fixture beside a compliant twin, the same technique `0-02` used for layering and `17-01` for tenant
scoping: a rule that has only ever been observed passing is not evidence.

Two words the review named are enforced only in `Ago.Chat.Domain` and `Ago.Chat.Contracts` —
`slot` and `service` — because .NET's dependency-injection vocabulary saturates the second and an
operator's capacity "slot" (`6-10`) legitimately uses the first. Those two assemblies are where a
violation would actually land, since a violation is a field on a message or a field on a DTO, and
neither contains DI vocabulary. **`worker` was tried and dropped**: it produced seven hits, none of
them a boundary crossing, because in a .NET service "worker" means a background thread and a
deployable. A signal that only ever fires falsely is not a signal.

### The kind is a string, not an enum

An enum would be a closed set AGO Chat owns, so every new kind any product ever produced would need a
member added here — and the first such member is the moment AGO Chat learned another product's
vocabulary. `MessageContentKind` validates shape (lowercase ASCII, `.`/`_`/`-`, 64 characters) and
never membership. A row holding some product's vocabulary is *data*; a `switch` over that vocabulary
would be *knowledge*.

### Actions are first-class, not fields inside the payload

**This is the decision the whole design turns on, and it is forced by the channel with no UI rather
than chosen for elegance.** Actions inside the payload would be simpler to model and would keep AGO
Chat's surface smaller. They would also be unreachable: a renderer for a text-only channel has to
*enumerate the choices* to print them as a numbered list, and it cannot enumerate anything inside a
document whose schema it is forbidden to know. Every channel adapter would then need a parser per
payload kind — the bespoke-per-channel shape the review rules out.

So the split is: **AGO Chat owns the actions' schema and reads it; AGO Chat owns no schema for the
payload and never reads it.** An action is a label and an opaque value, and nothing else — no styling
hint, no icon, no "primary", because a hint would be an opinion about another product's choice that a
text channel could not honour anyway.

### The body stays mandatory, and that *is* the rendering contract

A structured message still carries prose, and the prose is still required. One rule, and it is what
makes the whole thing work on a channel with no UI:

- **`body` is the fallback, and it is mandatory.** Any renderer on any channel can always print it.
- **`content` is an enrichment a renderer may use instead.** A browser draws a card; a text channel
  ignores it and loses nothing but polish.
- **`actions` are the choices, and they carry labels so a text renderer can number them.**

The worked example is a test (`StructuredContentRenderingTests`): one payload rendered as a UI element
and as `body` + `1) … 2) … 3) …` + "Reply with a number." The text renderer is **eleven lines** and
reads no field of the payload — proven by rendering a completely different payload through it and
asserting the output is byte-identical. A digit coming back resolves to the producer's own opaque
value by index.

### The return direction is an ordinary message

An action's reply is a normal send carrying the producer's own structured content, with the chosen
value inside it. There is no action endpoint and no routing, because routing an action to a product
would mean knowing which product produced it — the same knowledge in a different place, and it is
`21-01`'s question, not this one's.

### Storage: `text`, three nullable columns, one CHECK

Argued in full in `data-model.md`. In short: nothing ever queries into the payload **by design and
permanently**, so everything `jsonb` buys is a capability whose use would be an architecture
violation; `text` also round-trips a producer's bytes verbatim and TOASTs out of line; three NULLs
cost zero additional bytes on the prose messages that are all of them today; and the migration is a
catalogue-only change with no rewrite of a partitioned table.

### The size limit is a denial-of-service control

16 KB for the payload, 10 actions, 80/256 characters per label/value. **A ceiling, not a target, and
unmeasured** — but not arbitrary. This field rides the message-send path, which accepts input from
unauthenticated visitors on the public internet, and one send is stored forever, fanned out to every
connected participant and replayed on every history read. The action count in particular is bound by
**the weakest channel, not the database**: a numbered choice a person answers by replying with a digit
stops being answerable long before ten.

## Consequences

- **`21-01` is unblocked on its first question and only its first.** What carries the structure is
  now answered. **Who parses the intent** — turning "I'd like a haircut Tuesday" into a booking — is
  untouched, deliberately, and remains the first time either product would reference the other at
  all. It gets its own ADR when it is taken. This item must not be read as having answered it.
- **`20-06`'s slot picker renders through this**, not as browser-only markup, which is what makes the
  same interaction work on a channel with no widget.
- **Every existing client keeps working with no change.** The three wire fields are appended last and
  optional, and the three hub parameters are appended after `clientMessageId`, which SignalR binds
  positionally. A client built before this ignores three fields it has never heard of and keeps
  rendering `body` — which is only true *because* `body` stayed mandatory.
- **A payload is a place personal data can hide, and nothing can redact inside one.** The rule for
  producers is "put nothing in a payload you would not put in `messages.body`", and it is a rule
  rather than a control: enforcing it would mean AGO Chat validating a schema it must not own.
  `personal-data.md` carries the row, including the honest statement that erasure deletes the row or
  nothing.
- **`MessageAccepted` gained nothing.** The integration event already carries no body — "a consumer
  that needs it reads `GetConversationHistory`" — and a payload AGO Chat cannot interpret is the last
  thing that should travel on a topic other products' consumers read.
- **A duplicated mapping was removed on the way past.** `MessageHistoryItem` → `MessageDto` existed
  identically in `VisitorHub`, `OperatorHub` and `ResolveMessageDeliveryTargetsHandler`; a fourth
  field would have been a fourth chance for the fan-out copy and the local-echo copy of one message to
  disagree, which is `5-11`'s own failure mode, found live. It is now `MessageDtoMapper`.
- **The payload ceiling is stated twice** — `MessagePayload.MaxLength` and a Postgres CHECK. Accepted
  deliberately, with an integration test writing a payload at exactly the limit so the two cannot
  drift apart unnoticed.

## Alternatives considered

- **Give `Message` typed fields for what a booking needs** — a slot, a service, a confirm action.
  Rejected, and it is the alternative this ADR exists to refuse. It is the easy path, it would work,
  and it would make AGO Chat depend on AGO Calendar's domain through a data model rather than a
  `ProjectReference` — a dependency nobody reviews because nothing in the build shows it.
- **Actions inside the payload.** Rejected: unreachable by a renderer forbidden to know the payload's
  schema, which turns every channel adapter into a parser per payload kind. See above; this is the
  load-bearing rejection.
- **`jsonb` for the payload.** Rejected: everything it buys is querying into contents AGO Chat may not
  understand, paid for on every insert into the largest partitioned table in the system. It would also
  silently reorder keys and drop duplicates, breaking any producer that signs its payloads.
- **A child `message_actions` table.** Rejected: `messages` is `PARTITION BY RANGE`, so a child table
  needs its own partitioning or a foreign key pointing at a partitioned parent — the same reason
  `attachments.message_id` has no FK — and the hot keyset read would grow a join for a list empty on
  virtually every row.
- **One composite column holding kind, payload and actions together.** Rejected for a measurable
  reason rather than a stylistic one: three nullable columns cost zero additional bytes on a prose
  message, so the composite would have bought nothing and cost readability plus a converter around the
  aggregate.
- **Generalise `AttachmentId` into "the message's extra thing".** Rejected: an attachment is a
  reference to a file this product owns and verifies against `attachments` before a message may carry
  it (`5-03`). Merging the two drags file semantics into a field whose entire value is having none.
- **Validate the payload against a schema the producer registers.** Tempting, and it would catch a
  malformed card before it reached a client. Rejected: a registry of schemas is a vocabulary, and AGO
  Chat holding a vocabulary of another product's message kinds is the boundary crossing with an extra
  step. Shape validation (well-formed, an object, bounded) is the most this product can do without
  learning something.
- **Rich text in the same field.** Rejected and out of scope: formatting is a rendering concern for
  prose, and conflating it with structured content makes both harder.
- **Let a structured message omit its body.** Rejected — and this was the one alternative that would
  have quietly broken the whole design. A message with a beautiful card and no prose is well-formed,
  valid, storable and deliverable, and unreadable on SMS. The mandatory body is what makes the
  contract survive a channel with no UI.
