# a tenant can connect a channel without us

- **Stage**: 23
- **Status**: done — `ago-chat#213`, `ago-console#142`, `adr/0143`. The one remaining box (a real
  message through a real bot) needs the author personally and cannot be asserted by anything in this
  repository — split off as `25-08` rather than holding this item open for it. The five channels this
  item did not build a screen for are `25-09`.
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

- [x] A tenant connects a Telegram bot from the console and the screen tells the truth about the
      token, verified live at entry (`getMe`). **"A real message arrives" is a separate claim nothing
      in this repository can assert on its own — split off as `25-08`, the author's to close.**
- [x] A wrong token is refused at entry with what the provider said, not accepted and silently dead.
      And on every later read, not only at entry: a token that stops being valid afterwards is the
      case a check at entry cannot see (`adr/0143`).
- [x] No credential is ever rendered back after it is saved, asserted by a test — at two levels, both
      fault-injected: the response type is structurally incapable of carrying a token (a reflection
      test fails when a `Token` property is added), and the console DOM test fails when the token is
      deliberately leaked into the connected view.
- [x] Disconnecting stops delivery and leaves `adr/0116`'s foreign key intact — unchanged from
      `14-02`, which built it; this item added the screen that reaches it, with the consequence
      stated in the confirmation rather than discovered afterwards.

## What actually shipped, against the question this item asked itself

**"Six channels, one screen or six?"** turned out to be answered by scope, not by a generic shape:
this item built **one screen, for one channel** — `TelegramChannelPage`. The other five (MAX, VK,
Email, WhatsApp, Avito) each still have a working adapter and no console screen, exactly the gap this
item's own "What is actually true today" section described for all six before it shipped. That gap is
real, unbuilt work — filed as `25-09` rather than left as an open question with nothing pointing at
it.
