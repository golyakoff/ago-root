# 25-69 · No seeded role grants `conversation:close`

- **Stage**: 25
- **Status**: ready
- **Depends on**: `11-09` (done) - that item built the console's own ability to close a conversation;
  this one is about nobody being granted the permission to use it.
- **Found**: 2026-09-12, while landing `25-68` - closing the one live duplicate conversation through
  the real `CloseConversationHandler` application path was refused (`Conversation.Forbidden`) for the
  account's own operator, who holds both the "Operator" and "Admin" roles. Checked directly against
  the live deployment's `roles` table: `select name, permissions from roles where 'conversation:close'
  = any(permissions)` returns **zero rows** - no role in production grants this permission at all.

## What is actually true

`11-09` built the mechanism (`CloseConversationHandler`, gated on `Permission.ConversationClose`,
`docs/backlog/11-09-*` itself done). Nothing seeds or grants that permission to any role an operator
or administrator actually holds. The two roles that exist on the live deployment:

- **Operator**: `booking:cancel, booking:confirm, booking:mark_no_show, booking:reject,
  conversation:assign, conversation:note_write, conversation:read, conversation:send,
  conversation:tag, customer:edit, customer:read`
- **Admin**: `attachment:delete, calendar:configure, conversation:erase, site:configure, site:erase,
  site:export, site:manage_operators`

Neither carries `conversation:close`. An operator can open, read, assign, tag and message a
conversation, and an admin can even *erase* one outright (`conversation:erase`, a stronger, one-way
action) - but nobody, on any seeded role, can close one the ordinary way.

## Where this is likely to go wrong

- **This is a seed-data/role-grant gap, not a missing feature.** The permission and the handler both
  already exist and are already tested (`11-09`). The fix is granting the permission to the roles that
  should carry it, not building anything new.
- **Check whether this is seed-only or systemic before assuming the fix is one row.** If role creation
  (site registration, invite redemption) always stamps these same two role definitions, the fix is in
  whatever defines "Operator" and "Admin" by default, not a one-time `UPDATE` on the live deployment
  alone - a live-only fix would regrant nothing to a newly registered site.

## Done when

- [ ] An operator holding a role meant to include it can close a conversation through the real
      application path, proven on a fresh site (not just the one live account this was found on).
- [ ] Whichever role definition is authoritative (seed script, default-role factory, or both) carries
      `conversation:close`, so a newly registered tenant does not reproduce this gap.
