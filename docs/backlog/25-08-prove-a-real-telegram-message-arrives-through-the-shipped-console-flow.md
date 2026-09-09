# 25-08 · Prove a real Telegram message arrives through the shipped console flow

- **Status**: ready — **needs the author's own bot and a real message; nothing in this codebase can
  stand in for either**
- **Date found**: 2026-09-09, splitting `23-36`'s own last Done-when box off into its own number
- **Depends on**: `23-36` (built and merged, `ago-chat#213`/`ago-console#142`/`adr/0143`)

## Why this is split rather than left inside `23-36`

`23-36`'s Done-when box 1 named two different claims in one sentence: *"a tenant connects a Telegram
bot from the console"* (built, tested, merged) and *"a real message arrives"* (not something any test
in this repository can assert — it needs a live bot token and a person on the other end sending a
message). Everything the first claim needed has shipped. The second is the one promise this repository
cannot keep to itself, and rule 15 says a promise like that gets its own number rather than holding the
first one open indefinitely.

## What this item is

The author connects a real Telegram bot from `office.reserve-me.ru`'s console screen, sends it a
message from a real Telegram client, and confirms it arrives as a conversation an operator can answer.
Nothing to build — `TelegramChannelPage` and the ingestion path are already live. This item exists to
hold the one remaining fact open until it is checked, not to describe new work.

## Done when

- [ ] A tenant connects a real Telegram bot from the console.
- [ ] A real message sent to that bot arrives as a conversation in the console.
