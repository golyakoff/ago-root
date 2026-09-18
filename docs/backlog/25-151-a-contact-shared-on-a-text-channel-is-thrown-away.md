# 25-151 · A contact shared on a text channel is thrown away

- **Stage**: 25
- **Status**: done — `ago-chat#329`
- **Found**: 2026-09-18, scoping `25-138` (a read-only Opus analysis, verified against the code
  directly). Both Telegram's and MAX's inbound parsers drop any message with no text - a Telegram
  `contact` message or a MAX `contact`-type attachment is silently discarded today, whether the
  visitor shared it unprompted or in answer to anything.
- **Depends on**: none. Touches `ago-chat` only.

## What is actually true today

- `TelegramInboundMessageParser.cs:55-59` and `MaxInboundMessageParser.cs:41-45` both drop any update
  with no text body before it reaches anything else in the pipeline.
- `TelegramMessage` (`TelegramDtos.cs:30-34`) declares only `message_id`/`from`/`chat`/`text` - no
  `contact` field exists to deserialize a shared contact into. `MaxIncomingMessage`/`MaxMessageBody`
  (`MaxDtos.cs:29-41`) are the same shape, no `attachments`.
- `RecordVisitorContactDetailHandler` - the one place a `VisitorContactDetail` is ever written - is
  reachable only through two HTTP entry points (a visitor's own token, an operator's). Nothing in the
  channel-message pipeline calls it. **A text-channel visitor's phone, however it arrives, never
  becomes a `VisitorContactDetail`** - the operator console shows that visitor with no name and no
  phone, and the booking flow's own `ResolveKnownPhoneAsync` will ask them again on every future
  conversation, forever.

## Scope

- Extend `TelegramMessage`/`MaxIncomingMessage` (and whatever DTOs sit beneath them) to also carry a
  contact payload when present: Telegram's `contact` object (`phone_number`, `first_name`,
  `last_name?`, `user_id?`); MAX's `contact`-type attachment (`vcf_info`, `max_info`, `hash`).
- **Telegram**: accept the contact only when `contact.user_id == message.from.id` - the mandatory
  discriminator between "the sender shared their own number" and "the sender forwarded someone else's
  address-book entry." Telegram attaches no signature; this equality check is the entire trust.
- **MAX**: accept the contact only when `hash` verifies as HMAC-SHA256 of `vcf_info`, keyed with this
  site's own bot token - present only when the user shared their own contact via a
  `request_contact`-type button (`25-152`'s own outbound half, though this item does not depend on
  it - an unprompted share already produces the identical payload shape). **Verify this against a
  real MAX capture before trusting the field names above** - `MaxDtos.cs`'s own standing note says
  this integration's wire shapes were reconstructed without a live token.
- On acceptance, record a `Phone` `VisitorContactDetail` (and `Name`, if the payload carries one) for
  that conversation's visitor - reusing `RecordVisitorContactDetailHandler`'s existing write path via
  a new command (not widening `ReceiveChannelMessage` itself, which `ChannelPortTests.
  ReceiveChannelMessage_CarriesNoTimestamp` already guards against undocumented accretion) - the same
  "new sibling command" shape `14-12`'s own `/linkidentity` handling already uses.
- A contact that fails its own channel's discriminator (wrong `user_id`, bad `hash`) is rejected and
  logged, never recorded, never surfaces as an error to the visitor - the same "a malformed inbound
  fact never breaks the pipeline" posture this codebase already takes elsewhere.

## Where this is likely to go wrong

- This item does not touch consent. `RecordVisitorContactDetailHandler.ConsentSatisfiedAsync` already
  refuses to record a contact detail when a site has `RequireContactConsent` on and no consent is on
  file - a text-channel visitor has no way to satisfy that today, so this item's own write will be
  correctly refused on such a site until `25-153` lands. Confirm this refusal happens cleanly (no
  visitor-facing error, no crash) rather than assuming it and moving on.
- Don't build any outbound "please share your contact" affordance here - that is `25-152`'s own,
  separate promise. This item is inbound-only: stop throwing away what a visitor already sends.

## Done when

- [x] A Telegram `contact` message whose `user_id` matches the sender records a `Phone`
      `VisitorContactDetail` for that visitor
- [x] A Telegram `contact` message whose `user_id` does not match the sender is rejected and logged,
      never recorded
- [~] A MAX `contact` attachment whose `hash` verifies against the site's own bot token records a
      `Phone` `VisitorContactDetail`; one that fails verification is rejected and logged - verified
      against a real MAX capture, not only the documented wire shape. **Delivered against the
      documented wire shape only** - no real MAX bot token or captured `request_contact` payload was
      available; the exact field names, hash construction and digest encoding (assumed lowercase hex)
      are flagged as best-effort in `MaxDtos.cs` and the parser's own remarks, the same standing gap
      that file already carried. Live verification is a follow-up when a real MAX token exists.
- [x] A visitor's next booking finds the recorded phone via `ResolveKnownPhoneAsync`; the operator
      queue shows their name
- [x] On a site with `RequireContactConsent` on and no consent on file, the write is refused cleanly
      (no crash, no visitor-facing error) - this item does not need to fix that gap, only not break on
      it

## Outcome

New sibling command `RecordChannelVisitorContact` reuses `RecordVisitorContactDetailHandler`'s
existing write path (rate limits and consent gate included) rather than widening
`ReceiveChannelMessage` - `ChannelPortTests.ReceiveChannelMessage_CarriesNoTimestamp` still passes
unchanged. Telegram trust is `contact.user_id == message.from.id` (the entire mechanism - Telegram
signs nothing); MAX trust is HMAC-SHA256 of `vcf_info` keyed with the site's bot token, constant-time
compared. Full suite green: Domain 741, Application 1395, FakeCrm 21, Architecture 50, Concurrency
89, Integration 1363. `ago-chat#329`.
