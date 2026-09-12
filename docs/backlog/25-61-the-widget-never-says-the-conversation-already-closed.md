# 25-61 · The widget never says the conversation already closed

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md`

## What is actually true

After a conversation's hold-timeout expires and it closes, a visitor who still has the widget open
and tries to send another message sees the generic "Не удалось отправить." — indistinguishable from
a real network/server failure. The visitor has no way to know the actual reason is that the
conversation itself already ended.

## Scope

- When a send fails specifically because the conversation is closed (not a genuine network/server
  failure), show the visitor a distinct message saying so — the conversation has ended, rather than
  the generic send-failure note.
- If the widget can detect the closure proactively (e.g., a real-time signal it already receives)
  rather than only failing on the next send attempt, prefer surfacing it at the moment of closure —
  but at minimum, the send-failure path must distinguish "closed" from "actually failed to send."

## Where this is likely to go wrong

- **Don't collapse this into the same generic error path it's replacing.** The whole point is telling
  these two failure reasons apart; reusing one catch-all message for both would leave the bug in place
  under a different label.

## Done when

- [ ] A visitor who tries to send into a conversation that has already closed sees a message saying
      the conversation ended, not the generic "не удалось отправить" note.
- [ ] A genuine send failure (real network/server problem) still shows its own, correctly distinct
      message.
