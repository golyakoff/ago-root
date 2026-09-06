# a tenant can connect a channel without us

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-31` reserves the places (Каналы → Бот MAX, Бот Telegram, Другие каналы)
- **Decision**: `adr/0069` already decided how a channel credential is stored and encrypted

## Goal

A tenant who has a Telegram bot can connect it themselves.

## What is actually true today, found while drawing the navigation

**Six channel adapters ship and not one has a screen.** MAX (`14-02`), Telegram (`14-07`), VK
(`14-08`), Email (`14-09`), WhatsApp (`14-10`), Avito (`14-11`) are all registered unconditionally in
`ChatModule` and activated per site by a `channel_credentials` row — a row that today can only be
created **through the API**.

So the product supports six inbound channels and sells none of them, because connecting one requires
somebody with a terminal. That gap was invisible until the navigation had to find a place for each,
which is the honest reason this item exists now and not three stages ago.

## Why this is more than a form

**A channel credential is the most dangerous thing a tenant will ever paste into our console.** A
Telegram bot token is the bot; whoever holds it reads every message the bot receives. `adr/0069`
already encrypts them at rest with `CHANNELS_CREDENTIAL_ENCRYPTION_KEY` — `24-14` gave that key its
inventory row and classed it **Breaking** to rotate. This item is what puts real tenants' tokens
behind it.

Two consequences that shape the screen rather than decorate it:

- **The token is never echoed back.** Same discipline `ModuleEndpoints` already applies to a module
  credential: shown once at entry, never re-rendered, replaced rather than edited.
- **"Connected" must mean the provider agreed**, not that a string was saved. A screen that accepts a
  typo and reports success produces a tenant who believes they have a channel and has silence.

## Scope

- A screen per channel kind, or one screen with the kind chosen — that shape is part of the work.
- Enter a credential, verify it against the provider, show what the provider said.
- Disconnect, which unlinks rather than deletes (`ChannelIdentity.Unlink` already sets `Active = false`
  and `adr/0116` depends on that staying true).
- What the tenant sees for a channel that stopped working, because a bot token revoked at the provider
  is the ordinary failure and today nothing surfaces it.

## Out of scope

- Adding a seventh channel.
- Anything about `24-08`'s finding that **what each provider retains is not established**. That is a
  legal answer, not a screen, and the register already records it as unknown.

## Done when

- [ ] A tenant connects a Telegram bot from the console and a real message arrives.
- [ ] A wrong token is refused at entry with what the provider said, not accepted and silently dead.
- [ ] No credential is ever rendered back after it is saved, asserted by a test.
- [ ] Disconnecting stops delivery and leaves `adr/0116`'s foreign key intact.

## Open questions

- **Six channels, one screen or six?** They differ more than they look: Email is RFC-direct with no
  vendor, WhatsApp goes through Meta's own onboarding, Avito is an account rather than a bot. One
  screen that pretends they are the same shape will be wrong in four places.
