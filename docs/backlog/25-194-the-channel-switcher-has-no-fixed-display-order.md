# 25-194 · The channel switcher has no fixed display order

- **Stage**: 25
- **Status**: done — `ago-chat#349`
- **Found**: 2026-09-21, the author, reviewing the channel-switcher mockups (`25-192`).

## What was actually true

`IPublicChannelLinkReadStore`'s own SQL carries no `ORDER BY` at all - the order
`AuthEndpoints.VisitorSessionResponse.ChannelLinks` comes back in is whatever Postgres happens to
return, stable in practice but never a guarantee, and not a deliberate choice.

## The order, the author's own explicit choice

1. Max
2. ВКонтакте (Vk)
3. Telegram
4. WhatsApp

(Avito is not part of this list - see `25-195`.)

## Fix

`ChannelLinkUrlBuilder.DisplayOrder(ChannelKind)` - a fixed priority, lower sorts first, an unknown
kind sorts last rather than throwing. `AuthEndpoints.GetChannelLinksAsync` sorts the read store's
rows by it once, before building the response, so every caller (both the initial mint and a
renewal) gets the same order for free.

## Done when

- [x] `ChannelLinks` on the wire always comes back Max, Vk, Telegram, WhatsApp regardless of the
      order the underlying rows were connected in - proven by a real integration test that seeds
      them in the reverse order and asserts the response's own order, fails-before/passes-after
      confirmed directly.
- [x] `dotnet format`/build/full suite green (Domain 770, Application 1468, FakeCrm 21,
      Architecture 52, Concurrency 90, Integration 1487).
