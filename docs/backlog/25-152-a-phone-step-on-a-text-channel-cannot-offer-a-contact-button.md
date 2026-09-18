# 25-152 · A phone step on a text channel cannot offer a contact button

- **Stage**: 25
- **Status**: done — `ago-chat#330`
- **Found**: 2026-09-18, scoping `25-138`. Both Telegram and MAX have a native "share your own
  contact" affordance - a tappable button that sends the account's own registered phone number, no
  typing required. Neither is wired into `ago-chat`; both channels ask for a phone the same way today,
  as a plain typed-text question.
- **Depends on**: `25-151` (the button is useless if the resulting contact message is still thrown
  away on arrival). Touches `ago-chat` only.

## What each channel actually offers, verified against provider documentation

- **Telegram**: a `KeyboardButton` with `request_contact: true`, inside a `ReplyKeyboardMarkup` (a
  reply keyboard, not the inline buttons this codebase sends today). On tap, the client shows a native
  confirmation and the bot receives a `Message.contact` carrying the account's own registered number -
  private chats only (every Telegram conversation this product has is 1:1, so this is not a
  constraint in practice).
- **MAX**: a `request_contact`-type button inside an `inline_keyboard` attachment (MAX's own button
  vocabulary: `callback`, `link`, `request_contact`, `request_geo_location`, `open_app`, `message`,
  `clipboard`). At most three `request_contact`-type buttons per row. **Verify this against a real MAX
  capture before shipping** - the same standing caveat `25-151` names for `MaxDtos.cs`.
- Neither number is more "verified" than a typed one in the sense `20-09`/`14-15` already use that
  word - the author's own decision, 2026-09-18: this stays a better-quality *unverified* contact
  detail, not a new evidence source for `RequiresVerifiedPhone`. Do not touch
  `RouteConversationToModuleHandler`'s existing verified/unverified logic in this item.

## Scope

- `OutboundChannelMessage` (`Ago.Chat.Application.Abstractions.IInboundChannelAdapter`) gains **one**
  new, channel-neutral flag - e.g. `RequestContactIfSupported: bool` - set by
  `DeliverChannelMessageHandler` when the step being relayed has `content.Kind` of `form` or
  `verified_phone_form` and `content.fieldId == "phone"` (the identical discriminator `25-146`
  already uses on the widget side for the same step). **A flag expressing intent, not a rendering
  instruction** - the port asks "offer a contact affordance if you can," never "draw a reply
  keyboard"; a channel with no such affordance ignores the flag and sends the prose exactly as today.
  State this reasoning in the PR - it is the load-bearing layering choice this item makes, and the
  alternative (passing the full structured `MessageContent` to every adapter) was considered and
  rejected because it would drag `adr/0065`'s whole primitive vocabulary across a boundary six
  adapters currently stay ignorant of.
- Telegram's adapter builds a `ReplyKeyboardMarkup` with one `request_contact` button when the flag is
  set; MAX's adapter builds the equivalent `inline_keyboard` attachment. The other four adapters
  (VK, WhatsApp, Avito, Email) ignore the new flag - their own output must be byte-identical to today.
- The prose prompt itself is unchanged; typing a phone number back must still work exactly as today
  (the button is an addition, not a replacement) - a visitor who ignores the button and types anyway
  gets the identical outcome this step already produces.
- Write an ADR for the flag-vs-structured-content decision above - a real "what crosses this
  boundary and why" call `adr-writer` exists for.

## Where this is likely to go wrong

- **Do not build this against MAX's documented shape alone.** `25-151`'s own Done-when already
  requires a real MAX capture for the inbound half; this item's outbound half needs the identical
  verification before being trusted live - confirm the button actually renders and actually produces
  the contact payload `25-151` expects, against a real MAX bot, not only against the SDK's own model
  types.
- **No new step, no new gate.** This item answers the phone-collection step that already exists
  (`ModuleStepFactory.PhoneForm`, already positioned right before confirmation per `25-146`) - it must
  not add a round-trip for any visitor, including one who never intends to book.
- An arch test (extend `ChannelPortTests` or add a sibling) must prove no provider-specific vocabulary
  (a `ReplyKeyboardMarkup`-shaped type, a MAX attachment shape) crosses into `Application`/`Domain` -
  the flag itself is the only thing that crosses, and it says nothing about *how* a channel honors it.

## Done when

- [x] The phone step reaches a Telegram visitor with a working `request_contact` reply-keyboard button
      alongside the unchanged prose prompt
- [~] The phone step reaches a MAX visitor with a working `request_contact` inline button - verified
      against a real MAX bot, not only the documented shape. **Delivered against the documented outline
      only** - no real MAX bot/token was available, the same gap `25-151` already carries. Live
      verification is a follow-up once a real MAX token exists.
- [x] Typing a phone number in reply to either still works, unchanged
- [x] VK/WhatsApp/Avito/Email relay is byte-identical to today - the new flag changes nothing for a
      channel that ignores it
- [x] An arch test proves no provider-specific button/keyboard vocabulary crosses above
      `Infrastructure.*`
- [x] An ADR records the flag-vs-structured-content decision (`ADR-0176`)

## Outcome

`OutboundChannelMessage.RequestContactIfSupported: bool` (default `false`) - intent, never a rendering
instruction. `DeliverChannelMessageHandler` sets it via the identical `isPhoneCollectionStep`
discriminator `25-146` uses on the widget side. Telegram builds a `ReplyKeyboardMarkup`; MAX builds an
`inline_keyboard` attachment - both a `JsonIgnore(WhenWritingNull)` away from a byte-identical ordinary
reply (a real bug caught by the byte-identical proof tests before it shipped). Button label is a fixed,
unlocalized string - a named, accepted cosmetic gap (`ADR-0176`). Full suite green: Domain 741,
Application 1400, FakeCrm 21, Architecture 52, Concurrency 89, Integration 1375. `ago-chat#330`,
`ADR-0176`.
