# 25-195 · Should Avito join the channel switcher, and what would it link to?

- **Stage**: 25
- **Status**: needs a decision
- **Found**: 2026-09-21, the author, specifying the channel switcher's display order and naming
  Avito as a fifth entry. Filed as the question per `CLAUDE.md` rule 14 - this is a product/scope
  decision, not a found defect, and the honest answer decides something rather than merely fixing
  something.

## Why this isn't just "add one more line to the order"

`ChannelLinkUrlBuilder`'s own scope, decided in `25-147`/`25-148`/`25-149` and restated in its own
doc comment: **Avito never reaches `BuildUrl` at all**, because `IPublicChannelLinkReadStore`'s own
SQL deliberately never produces a row for it - `25-147`'s own "store nothing" decision for Avito's
`public_handle`.

The reason is structural, not an oversight: every other channel here has a stable, site-level
"message us" surface a visitor can be handed a link to and land in a conversation with *this shop*
- a Telegram bot's `t.me/<username>`, a VK community's `vk.me/club<id>`, a WhatsApp number's
`wa.me/<digits>`. **Avito has no equivalent.** An Avito conversation is anchored to a specific
listing (`item_id`) - `ChannelIdentity`'s own remarks state this plainly, and
`Ago.Chat.Infrastructure.Avito.AvitoChannelAdapter` is built around exactly that address shape. A
seller has no single, stable "start a chat with my shop" URL Avito exposes the way the other four
providers do.

## The actual open questions

1. **Is there a real Avito surface worth linking to at all** - e.g. the seller's public profile
   page (`avito.ru/user/...`), which a visitor could browse but which does not open a conversation
   the way every other row in this switcher does? If the honest answer is "no direct-to-chat link
   exists," a switcher entry that behaves differently from every sibling row (browse instead of
   message) may do more harm than good - visitors would reasonably expect every row here to behave
   the same way.
2. **If a profile-only link is judged worth it anyway**, does it need visibly different treatment
   in the UI (a distinct label like "View us on Avito" rather than an ordinary channel row), so a
   visitor isn't surprised that clicking it does not start a chat?
3. **Where would the profile URL itself come from** - a new, real field an operator sets by hand
   (there is no read-time-derivable value the way `channel_credentials` already gives VK's numeric
   community id), which is new schema and a new console field, not something `25-147`'s existing
   read store could grow into.

## Out of scope until answered

No code changes - this item exists to get the three questions above a real answer before `25-194`'s
own fixed order, or any future channel-switcher work, is asked to make room for a fifth entry that
does not yet have an agreed shape.

## Done when

- [ ] The author has answered whether Avito belongs in the switcher at all, and if so, what it
      links to and how that link is captured.
- [ ] If the answer is yes, a new, separate implementation item is filed with its own number,
      carrying the concrete shape decided here.
- [ ] If the answer is no (for now or permanently), this item is closed as not-planned, with the
      reason recorded here.
