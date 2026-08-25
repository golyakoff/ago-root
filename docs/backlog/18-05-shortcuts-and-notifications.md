# Keyboard shortcuts, and being told when something needs you

- **Stage**: 18
- **Status**: ready
- **Depends on**: `11-06-operator-workspace.md` (shipped) — this extends its attention model rather
  than replacing it

## Goal

An operator working several conversations moves between them without the mouse, and finds out that a
new one arrived without watching the tab.

## Context to read first

`ago-console/src/workspace/` and `11-06`'s own scope — it already ships Enter/Shift+Enter, an unread
badge and a document-title count, and it deliberately named "a keyboard-shortcut system" and "desktop
notifications and sound" as out of scope for a stage about appearance. This item is that deferral
coming due, and it should extend `attention.ts` rather than add a second idea of what needs attention.
`docs/backlog/5-15-*` — unread is now cleared server-side, so the badge means something durable and a
notification can be trusted not to fire for something already read.

## Scope

- A small, discoverable set of shortcuts: move between conversations, focus the composer, close, and
  whatever the workspace's own layout makes obvious. Discoverable means listed somewhere in the
  interface, not only in a file.
- Desktop notifications for a newly assigned conversation, **off until the operator turns them on** —
  the browser permission prompt on first load is the single most common way a product teaches people
  to click Block forever.
- Sound as a separate switch from notifications, because the people who want one frequently do not
  want the other.
- Respect the existing state: nothing fires for a conversation the operator is already looking at.

## Out of scope

- A command palette. A bigger interaction idea; if the shortcut list grows enough to want one, that is
  its own item with its own argument.
- Notifications when the tab is closed (push, service workers) — a different mechanism entirely, and
  it needs a subscription store and a server-side sender.
- Configurable key bindings.

## Done when

- [ ] The shortcuts work and are discoverable from inside the console.
- [ ] Notifications and sound are separate, both default off, and neither fires for the conversation on
      screen.
- [ ] Verified live with two browsers, the same bar `11-06` held.

## Open questions

None.
