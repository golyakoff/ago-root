# Unverified contact details

- **Stage**: 14
- **Status**: done (`ago-chat#137`, `ago-console#71`, merged 2026-08-30)
- **Depends on**: `adr/0079-verified-channel-identity-linking-and-a-preferred-reply-channel.md` - the
  "why this is not a `ChannelIdentity`" reasoning. Independent of `14-12`/`14-13` - buildable in any
  order relative to them, and touches none of their files.

## Goal

An operator can record a phone number, email, or other contact fact a visitor mentioned, even for a
channel this system has no adapter for at all (SMS/email, both still unbuilt - `14-03`/`14-09`) and can
therefore never verify. A small, honest reference note for the operator's own use, not a routable
identity.

## Why this is not a `ChannelIdentity`, restated from the ADR

A `ChannelIdentity` is only ever created by evidence - a real inbound message, or `14-12`'s real
confirmation code. A value an operator types because a visitor said it out loud has none of that. Storing
it as a `ChannelIdentity` would let an unverified, hand-typed value silently become a real send target
the moment a matching adapter is later built - this item keeps that door shut by construction.

## Scope

- **Domain**: a new, small aggregate (`VisitorContactDetail`: id, `VisitorId`, kind - a small closed
  enum, `Phone`/`Email`/`Other` - value, free text bounded the same way `MessageBody` already is,
  `RecordedByOperatorId`, `RecordedAt`). No uniqueness constraint - a visitor may plausibly have more
  than one phone number recorded, and nothing here needs to disambiguate them.
- A handler to record one, gated on `Permission.ConversationSend` (the same reasoning `14-12`'s own
  request-a-link endpoint uses: recording a fact told to the operator inside a conversation is not more
  sensitive than replying in it), and one to delete a mistaken entry, gated the same way (no separate
  "unlink" permission here - there is no routing capability to protect, only a note).
- Console: a small block on `VisitorPanel`, beside (not merged into) `14-12`/`14-13`'s own channel-
  identity panel - a materially different trust level deserves to stay visually distinct, the same
  reasoning `18-14`'s own report kept its honesty caveat off `18-10`'s shared table.

## Out of scope

- Any attempt to verify a recorded detail - that is exactly what `14-12` is for, for channels that have
  an adapter. This item is deliberately for the ones that do not, or for information an operator wants
  on record without going through verification at all.
- Automatic extraction from message text (regex/NLP-detecting a phone number in a sentence) - manual
  only in this item, matching `docs/adr/0078`'s own staged-automation discipline; an AI-assisted version
  is a future item, not a variation of this one.
- Using a recorded detail for delivery in any way - it is not a `ChannelIdentity` and never becomes one
  through this item.

## Done when

- [ ] An operator can record and later delete a contact detail on a visitor, proven by a test.
- [ ] The console shows recorded details on the visitor panel, distinct from `14-12`'s own linked-
      channels list.
- [ ] Cross-site isolation is proven by a test.

## Open questions

None.
