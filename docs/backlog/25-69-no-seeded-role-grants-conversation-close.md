# 25-69 · No seeded role grants `conversation:close`

- **Stage**: 25
- **Status**: done — `ago-chat#285`. Both Done-when boxes closed; see the note below for what remains
  as a separate, non-Done-when operational step.
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

- [x] An operator holding a role meant to include it can close a conversation through the real
      application path, proven on a fresh site (not just the one live account this was found on). —
      `FreshSiteOperatorConversationCloseTests`: registers a fresh site through the real
      `RegisterSiteHandler` (no hand-seeded role), then calls the real `CloseConversationHandler` as
      the operator that registration itself created. Confirmed red against the unfixed array before
      the fix, green after — independently re-run by the managing session, not just the worker's claim.
- [x] Whichever role definition is authoritative (seed script, default-role factory, or both) carries
      `conversation:close`, so a newly registered tenant does not reproduce this gap. — confirmed
      systemic rather than seed-only: `RegisterSiteHandler.OperatorRolePermissions` **and**
      `MintDemoTenantHandler`'s own parallel copy both carry it now, Operator-scoped for the same
      reason `23-69`'s `ConversationMarkSpam` is — ending a conversation is the ordinary, in-the-moment
      action an operator takes dozens of times a shift, not a configuration or compliance act.

## What this does not reach

**The live deployment's already-existing "Operator" role rows are not retroactively granted this
permission** — a seed-default change only affects sites registered from here on. Neither Done-when box
above asked for a live backfill (unlike, say, `23-85`'s own explicit walkthrough requirement), so this
is a separate, later operational step rather than unfinished scope: apply it through `25-76`'s own
`AddRolePermissionsAsOwnerHandler`/console tool, once that ships live, or by hand sooner if wanted. Not
done tonight — deliberately left for the author's own call on timing, since it touches live tenant
permissions rather than only a seed default.

Verified: `ago-chat` full suite green (`dotnet format --verify-no-changes` clean, `dotnet build -c
Release` zero warnings, `dotnet test -c Release` zero failures — Domain.Tests 692, Application.Tests
1239, FakeCrm.Tests 21, Architecture.Tests 46, Concurrency.Tests 87, Integration.Tests 1196), all
independently re-run by the managing session.
