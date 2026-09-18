# ADR-0176: A channel's contact-sharing affordance crosses the port as one bool, never as structured content

- **Status**: Accepted
- **Date**: 2026-09-18
- **Stage**: 25
- **Item**: `25-152` (a phone step on a text channel cannot offer a contact button), on top of `25-151`
  (a contact message arriving on Telegram or MAX is no longer thrown away)
- **Relates to**: `adr/0006` (one abstraction behind every external transport, "largest common
  denominator that does not lie"), `adr/0055` (`IInboundChannelAdapter`'s own outbound-only shape and its
  channel-neutral `OutboundChannelMessage`), `adr/0065` (the closed `PrimitiveKinds` vocabulary a module
  step is expressed in), `25-146` (the widget's own `isPhoneCollectionStep` discriminator, the precedent
  this item's server-side discriminator mirrors)

## Context

Telegram and MAX each offer a native "share your own registered phone number" affordance - a tappable
button that produces a contact message with no typing required (a `KeyboardButton` with
`request_contact: true` inside a `ReplyKeyboardMarkup` for Telegram; a `request_contact`-type button
inside an `inline_keyboard` attachment for MAX). Neither was ever wired up on the outbound side: both
channels ask for a phone number today the same way - a plain typed-text prompt, rendered by
`PrimitiveTextRenderer` from the module's own `PrimitiveKinds.Form`/`VerifiedPhoneForm` step. `25-151`
is what makes offering the button worth building at all: before it, a contact message the button
produced would have been silently dropped on arrival.

`IInboundChannelAdapter` (`adr/0055`) exists precisely to keep `Ago.Chat.Application` ignorant of what a
provider's wire protocol looks like - `OutboundChannelMessage` is Telegram, MAX, VK, WhatsApp, Avito and
Email's one shared shape, "the largest common denominator that does not lie" (`adr/0006`). Six adapters
implement it today; only two have anything resembling a contact-sharing button, and the shapes those two
use share nothing structurally - one is a keyboard replacing the on-screen keys, the other is an inline
attachment beside the message body. Whatever crosses the port to trigger this behaviour has to mean the
same thing to all six adapters, including the four with no such affordance at all, or the port stops
being a boundary and becomes a leaky abstraction six call sites each have to know to ignore correctly.

Separately, `DeliverChannelMessageHandler` already has a proven, narrow way to recognise "this step is
asking for a phone number": `content.Kind` is `PrimitiveKinds.Form` or `PrimitiveKinds.VerifiedPhoneForm`
and `content.Payload`'s own `fieldId` is `"phone"` - the exact discriminator `25-146` established for the
widget's own `isPhoneCollectionStep`, reading the identical wire fields a module already sends for this
step and no others. The question this item had to settle was not *how to detect* the phone step (already
solved) but *what to hand the two capable adapters once detected*, without teaching the four incapable
ones anything about buttons at all.

## Decision

**`OutboundChannelMessage` gains one new field, `RequestContactIfSupported: bool`, defaulted to
`false`.** `DeliverChannelMessageHandler` sets it to `true` exactly when `IsPhoneCollectionStep` above is
true, and passes it through unconditionally - it does not know or care which channel is on the other
end. Each adapter decides for itself what, if anything, that `true` means:

- `TelegramChannelAdapter`/`TelegramApiClient` build a `ReplyKeyboardMarkup` with one `KeyboardButton`
  (`request_contact: true`), alongside the unchanged prose text.
- `MaxChannelAdapter`/`MaxApiClient` build an `inline_keyboard` attachment carrying one
  `request_contact`-type button, alongside the unchanged prose text.
- `VkChannelAdapter`, `WhatsAppChannelAdapter`, `AvitoChannelAdapter` and `EmailChannelAdapter` never read
  the field at all - their output is byte-identical to what it was before this item, flag set or not.

The flag is **intent, not a rendering instruction**: the port asks a channel to "offer a contact
affordance if you have one," and says nothing about what that affordance looks like. This is the load-
bearing layering choice - a channel with no such affordance costs nothing to ignore a `bool` it does not
read, where it would have cost a real decision (accept and mis-render, or explicitly branch and discard)
had the port instead handed every adapter something shaped like an actual button.

The button label itself (`"Share phone number"`) is a fixed, unlocalized string, built inside each wire
client (`TelegramApiClient.SendMessageAsync`, `MaxApiClient.SendMessageAsync`) - the one cosmetic gap
this decision accepts rather than threads a `Locale` through `OutboundChannelMessage` for. See each
class's own remarks.

**Live-verification caveat, carried over from `25-151`.** MAX's outbound button shape
(`MaxOutboundAttachment`/`MaxInlineKeyboardPayload`/`MaxInlineKeyboardButton`) is this item's own
best-effort reconstruction from MAX's documented outline (button vocabulary and the "at most three
`request_contact` buttons per row" rule are both stated plainly; the exact envelope wrapping them is
not), not a confirmed request/response capture against a live bot - no MAX token was available while
this item was built. Telegram's shape carries no such caveat: `ReplyKeyboardMarkup`/`KeyboardButton` are
both fully specified in Telegram's own public Bot API documentation.

## Consequences

- Adding a phone-collection affordance to a seventh channel in the future (SMS, say, if it ever gains one)
  costs one new arm inside that channel's own adapter/client pair and zero changes to
  `DeliverChannelMessageHandler` or the port - the same "nothing in Domain, Application or the pipeline
  changes" test `adr/0055` already holds a new channel to.
- The flag says nothing about *whether* the affordance rendered correctly or was tapped - a Telegram
  visitor who ignores the button and types a phone number gets the identical outcome as before this item,
  which is deliberate (Done-when 3) but also means this flag, by itself, proves nothing about visitor
  behaviour; only `25-151`'s inbound contact handling proves the round trip actually completes.
- A future reader of `OutboundChannelMessage` sees a `bool` with no hint of what it renders as on either
  of the two channels that honour it - the two adapters' own class-level remarks are the only place that
  mapping is written down; there is no compiler-checked link between the flag and either wire shape.
- MAX's own button envelope is unverified against a live bot, so a real capture could reveal the actual
  wrapping differs from `MaxOutboundAttachment`'s own shape (wrong field names, a different type string,
  buttons not nested in rows) - this is shipped anyway, flagged here and in code, rather than blocked on
  access this item does not have.
- Two DTOs (`TelegramSendMessageRequest.ReplyMarkup`, `MaxSendMessageRequest.Attachments`) each needed an
  explicit `JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)` to keep an ordinary reply
  byte-identical to before this item - `System.Text.Json`'s default is to serialize a `null` property
  explicitly, which would have added a `"reply_markup":null"`/`"attachments":null` key no provider had
  ever seen from this codebase before, violating Done-when 4 by a fraction of a diff the tests below
  catch but a hand review easily would not.

## Alternatives considered

- **Pass the full structured `MessageContent` (kind, payload, actions) to every adapter, and let each one
  decide what to render from it.** Rejected: this would drag `adr/0065`'s whole primitive vocabulary -
  every `PrimitiveKinds` member, the payload's field names, the action-value contract - across a boundary
  six adapters currently stay completely ignorant of. VK, WhatsApp, Avito and Email would each need to
  either actively ignore fields they have no business knowing exist, or (worse) some future change would
  quietly start branching on `content.Kind` inside an adapter, the exact "provider vocabulary above
  Infrastructure" failure `ChannelPortTests.NoProviderVocabulary_AppearsAboveInfrastructure` exists to
  catch, just inverted (Chat's own primitive vocabulary leaking *into* a channel adapter instead of a
  provider's vocabulary leaking *out*). A one-`bool` flag is answerable with a single `if` an adapter can
  ignore entirely; a structured payload is not answerable at all without first understanding a vocabulary
  the adapter was never meant to know.
- **A `ChannelKind`-keyed lookup inside `DeliverChannelMessageHandler` that pre-renders each channel's own
  button shape and attaches it as an opaque blob.** Rejected: this reintroduces exactly the "Application
  knows what a Telegram keyboard looks like" violation the port exists to prevent, just moved one call
  site earlier than the naive version - the handler would need a `switch` over `ChannelKind` naming
  Telegram and MAX by name, which `ChannelPortTests.NoProviderVocabulary_AppearsAboveInfrastructure`
  already refuses in this exact file.
- **A second, narrower port (`IContactRequestingChannelAdapter`) implemented only by Telegram and MAX,
  checked with an `is`-pattern before falling back to plain `IInboundChannelAdapter.SendAsync`.**
  Rejected as premature generalisation for a two-implementer, one-method distinction: it would require
  `InboundChannelAdapterRegistry` (or its caller) to know which channels might support the optional
  interface, adds a second dispatch path `DeliverChannelMessageHandler` has to keep in sync with the
  first, and buys nothing a plain `bool` on the existing single call does not already give at zero extra
  surface area.
