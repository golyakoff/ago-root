# A message can carry structure the conversation does not understand

- **Stage**: 14
- **Status**: done
- **Decision**: `adr/0061` — a message can carry structure AGO Chat does not understand
- **Depends on**: nothing. `14-01` (channel identity) is merged and this sits beside it rather than on
  top of it.
- **Blocks**: `21-01`, which cannot choose between its three candidate directions until this exists;
  `20-06`, whose slot picker must render through this rather than as browser-only markup.

## Goal

`Ago.Chat.Domain.Message` can carry a **kind**, an **opaque structured payload** and a set of
**actions** — and AGO Chat never interprets any of them. A channel adapter or a client renders what it
is given; an action posts back to whoever produced it.

## Why this exists, and why it is the only addition the boundary review asked for

`reviews/2026-08-26-platform-boundary.md` tested three propositions across three passes and concluded
that the platform/product boundary should not move. This is the one thing it found missing.

Today a `Message` is a `MessageBody` (prose) plus an optional `AttachmentId`. There is no third shape.
That is fine while every conversation is a human typing at another human — and it stops being fine the
moment a *product* needs to say something into a conversation.

The product model makes that unavoidable rather than hypothetical. A booking must be reachable from
the widget, from Telegram, from MAX and from SMS, and there are shops that run with **no widget at
all**. So a booking interaction cannot be widget UI and cannot be bespoke per channel: it has to be
something the conversation itself carries.

## The property that makes this worth doing carefully

**AGO Chat must not learn what a booking is.**

That is the whole point, and it is easy to lose. If `Message` grows booking-shaped fields — a slot, a
service, a confirm action with known semantics — then AGO Chat depends on AGO Calendar's domain, which
is exactly the product-to-product dependency the repository split exists to prevent, arrived at
through a data model instead of a `ProjectReference`.

So the payload is **opaque to AGO Chat**: stored, sequenced, delivered and rendered, never validated
against a schema AGO Chat owns and never branched on. AGO Chat knows the payload exists and how big it
may be. It does not know what is in it.

The reviewer's test for whether this was built correctly: **`Ago.Chat.*` contains no type, field,
constant or branch naming a booking, a slot, or a service.**

## Context to read first

`docs/reviews/2026-08-26-platform-boundary.md`, second and third passes — the reasoning above in full,
including what would make it wrong. `docs/architecture/data-model.md`'s `messages` section and
`adr/0019` (partitioning widened the unique index) — this adds a column to a partitioned table that is
already the largest in the system, so the storage decision is not free. `docs/conventions/api-design.md`
— the wire shape is a versioned contract the widget, the console and every future channel adapter read.
`docs/architecture/personal-data.md` — an opaque payload is a place personal data can hide, and the map
has to say what may go in it.

## Scope

- **The domain shape**: a message kind, a payload, and zero or more actions. Decide and record whether
  actions are part of the payload or a first-class list — the second is easier to render generically
  and harder to keep opaque.
- **Persistence**: how the payload is stored on `messages`, given that table's partitioning and size.
  `jsonb` and a text column are both defensible; state the reasoning, including whether anything ever
  needs to query *into* the payload (if the honest answer is "no, by design", say so, because it
  decides the column type).
- **A size limit**, chosen and enforced. An opaque field with no ceiling is a denial-of-service surface
  on a path that already accepts unauthenticated input.
- **The wire contract**, versioned per `api-design.md`, in both directions — down to a client and back
  from an action.
- **Rendering contract for a channel with no UI.** This is the half that is easy to skip and is the
  reason the item exists: a payload that only a browser can render fails `21-01` on arrival. It does
  not need a Telegram adapter to prove it — it needs the contract to be expressible as text plus a
  numbered choice, demonstrated by one worked example.
- **`personal-data.md`** gains what may and may not travel in a payload.

## Out of scope

- **Any actual booking content.** This item ships the envelope. `20-06` and `21-01` fill it.
- **Intent parsing** — turning "I'd like a haircut Tuesday" into a booking. That is `21-01`'s second
  open question and it is a genuinely separate decision (see below).
- **Attachments.** `AttachmentId` stays as it is; this is not a generalisation of it, and merging the
  two would drag file semantics into a field that must stay opaque.
- **Rich text.** Formatting is a rendering concern for prose, not a structured payload, and conflating
  them makes both harder.

## Done when

- [x] A message with a kind, a payload and actions round-trips: persisted, sequenced, delivered over
      the hub, and echoed with its `clientMessageId` like any other message.
      (`StructuredMessageContentPersistenceTests`, six tests against real Postgres: through the EF
      aggregate, through the Dapper read model, and onto the wire DTO. Both read paths are asserted
      because they are genuinely different code and `5-11`'s own finding was a field that arrived
      correctly through one and as `undefined` through the other. The delivery half is the same
      `MessageDtoMapper` all three delivery sites now share — that duplication was removed on the way
      past, since a fourth field would have been a fourth chance for the fan-out copy and the local
      echo of one message to disagree.)
- [x] An architecture test asserts **no type, field, constant or branch in `Ago.Chat.*` names a
      booking, a slot or a service** — the opacity property, enforced rather than intended.
      (`MessageOpacityTests` + `MessageOpacityRule` + `MessageOpacityExemptions`, the same
      rule/exemptions/violating-fixture shape `17-01` used for tenant scoping. It reads compiled IL
      — type, field, property, method, parameter, enum-member names and `ldstr` literals — across
      **all nine** `Ago.Chat.*` assemblies, hosts included, matching whole words rather than
      substrings. Proven able to fail by a permanently violating fixture in the build, and by
      mutation: adding `Message.BookingReference` turns it red naming the field, its backing field
      and its getter.
      **Two findings about the reviewer's own word list, from running it:** `worker` had to be
      dropped — seven hits, none a boundary crossing, because in .NET it means a background thread
      and a deployable; and `slot`/`service` are enforced only in `Domain`/`Contracts`, where DI
      vocabulary cannot appear and where a violation would actually land. One argued exemption
      exists, for `6-10`'s capacity-slot metric description.)
- [x] The size limit is enforced and proven by a test that fails without it.
      (16 KB payload, 10 actions, 80/256 per label/value — a ceiling, unmeasured, and stated as
      such. Enforced in the domain and, for the payload, again as a Postgres CHECK, because this
      is an opaque field on the one write path that accepts unauthenticated input. The duplication
      of the number is deliberate and has its own test writing a payload at exactly the limit, so
      the two statements of it cannot drift apart unnoticed.)
- [x] One worked example shows the same payload rendered two ways: as a UI element, and as text plus a
      numbered choice a person could answer over SMS.
      (`StructuredContentRenderingTests`. The text renderer is eleven lines and reads no field of
      the payload — proven by rendering a *different* payload through it and asserting the output
      is byte-identical. A reply of "2" resolves back to the producer's own opaque value by index.
      The example is deliberately **not** a booking: writing one would have put another product's
      vocabulary into `Ago.Chat.Domain.Tests`, which is the exact thing the opacity rule forbids —
      a boundary crossing performed by the test that exists to prove the boundary holds.)
- [x] `personal-data.md` says what may travel in a payload, and `data-model.md` records the storage
      decision with its reasoning.
      (Both done. The personal-data row is honest about the thing that makes an opaque field worse
      than a body: a body can at least be swept for a substring, a payload has no schema anyone
      here knows, so erasure deletes the row or nothing. The producer rule — "put nothing in a
      payload you would not put in `messages.body`" — is a rule rather than a control, and the
      file says so, because enforcing it would mean AGO Chat validating a schema it must not own.)

## Open questions

**Who produces the payload, and how it reaches AGO Chat.** This item can be built with the payload
arriving through the ordinary send path, which is enough for `20-06` (the widget talks to both
backends). `21-01` needs more: something must decide that an inbound text is *about* booking. That is
the decision the boundary review flagged as **the first time either product would reference the other
at all**, and it deserves its own ADR when it is taken — not this item's to answer, and this item must
not quietly answer it by making the payload less opaque.

## What shipped, and what it changed

Full reasoning is `adr/0061`. What is worth flagging here:

- **The body stayed mandatory, and that is the rendering contract.** A structured message still
  carries prose. `body` is the fallback any channel can print, `content` is an enrichment a rich
  client may use instead, and `actions` are the choices with labels so a text renderer can number
  them. The one alternative that would have quietly broken the design was allowing a structured
  message with no body: well-formed, valid, deliverable, and unreadable on SMS.
- **Actions are first-class, not fields inside the payload** — forced by the channel with no UI rather
  than chosen. A text renderer must *enumerate* the choices, and it cannot enumerate anything inside a
  document whose schema it is forbidden to know. So AGO Chat owns the actions' schema and reads it,
  and owns no schema for the payload and never reads it.
- **The kind is a string, not an enum.** An enum is a closed set AGO Chat would own, and its first new
  member would be the moment AGO Chat learned another product's vocabulary.
- **`text`, not `jsonb`.** Nothing queries into the payload by design and permanently, so everything
  `jsonb` buys is a capability whose use would be an architecture violation — paid for on every insert
  into the largest partitioned table in the system.
- **The return direction needed no new concept.** An action's reply is an ordinary message carrying
  the producer's own structured content. A dedicated action endpoint would have had to know which
  product to route to, which is `21-01`'s question wearing different clothes.
- **`21-01`'s second question is untouched.** Who parses intent remains unanswered and unanswerable
  from here; nothing in this item made the payload less opaque in order to reach it.

Deliberately left: any booking content (`20-06`, `21-01`); intent parsing (`21-01`, and its own ADR);
attachments (`AttachmentId` is unchanged and is not generalised); rich text.
