# the team has one chat of its own, and the tenant is visible in it

- **Stage**: 23
- **Status**: done (2026-09-06). One room per site, a server-assigned sequence, outbox fan-out, and
  the reserved nav entry turned into a real screen.
- **Depends on**: `23-31` reserves its place in the navigation (Команда → Общение)
- **Decision**: the author's, 2026-09-06 — **one chat, not channels**

## Goal

People working the same queue can talk to each other without leaving the console, and it is obvious
who among them speaks for the business.

## Where this came from

A design pass against Jivo, which has «Группы» — several named internal chats («кофе-брейк»,
«Работа»). **We deliberately take one chat rather than channels**: a tenant with four operators does
not need a channel structure, and the moment there are two rooms somebody has to decide which one a
message belongs in.

We have nothing of the sort today. Every conversation in this system is with a **visitor**; there is
no writing surface between colleagues at all.

## The one thing that is not obvious

**The tenant must be visible as the tenant.** In a flat room of equals, the person who can grant
permissions, buy modules and close the account reads as just another name — and "the owner said so"
is a different weight from "a colleague said so". A label on their messages, not a separate room.

## Scope

- One chat per tenant, every operator of that tenant in it, no way to create a second.
- The account owner is labelled in the room. Which roles carry the label is part of this item; that
  it is visible is not negotiable.
- Messages are the tenant's own data: they live and die with the site, and `personal-data.md` gains
  a row — this is a **second kind of message store** in a system whose entire erasure and export
  machinery was built around visitor conversations.
- Realtime, on the transport that already exists. A team chat that needs a reload is not one.

## Out of scope

- **Moderation and deletion — `23-33`, deliberately after this.** Building the room and building the
  power to police it are two promises; the first is useful without the second and the second is
  meaningless without the first.
- Channels, threads, reactions, files, mentions, unread-per-person. Every one is a real feature and
  none is needed for a room of four people to say "I'm taking the angry one".
- Anything reaching a visitor. This surface is invisible to them by construction.

## Done when

- [x] Operators of one tenant can write to each other and see it arrive without reloading.
- [x] The owner is visibly the owner.
- [x] An operator of another tenant cannot read a word of it — asserted the way every other
      tenant-isolation test in this codebase is.
- [x] `personal-data.md` carries the store, its retention and what erases it.
- [x] Erasing the site erases the room.

## Open questions

- **Does a message here reach anybody who is offline?** A team chat nobody sees until they log in is
  a noticeboard, which may be exactly right — or may be the reason nobody uses it. Notification is
  not in this item, and whether it needs to be is worth answering before it ships rather than after.

## Outcome

`ago-chat#206`, `ago-console#135`, and this change for the documents it made incomplete.

**"The owner is visibly the owner" was answered with the capability, not the person**, and that is the
one place this item settled something the text did not. `ago-chat` has no single-owner concept:
`RegisterSiteHandler` grants the registrant both seeded roles, and a later invite can grant Admin to
anybody else. So the badge reads `Permission.SiteManageOperators`. **A site with two Admins labels
both**, which is stated in the handler's own doc comment rather than discovered later. `ago-calendar`
answered the same question differently (`adr/0083`, a dedicated flag); doing that here would have
meant new domain state and a second migration for a badge.

**Ordering is a sequence and the race is proven**: an atomic
`UPDATE sites SET team_chat_last_sequence = ... + 1 RETURNING` in the insert's own transaction, shown
against twenty concurrent sends. Replacing it with a read-then-write reddens with a real `23505`.

**Two placements worth remembering.** The sequence is a column on `sites` rather than a
`team_chat_rooms` table, because every site row exists before any operator can post - there is no
"does the room exist yet" question for a second table to answer. And fan-out goes through the outbox
and a consumer rather than straight from the hub: the lighter shape was considered, since a realtime
push has no dual-write hazard, and refused because nothing in this codebase calls
`INodeFanoutPublisher` outside an outbox-driven consumer.

**A real bug the ux-gate caught that no unit test could.** The first cut of the screen called
`getTeamHistory` on mount, and `OperatorConnectionProvider` starts every session in `"connecting"` -
so a fresh load threw *"no connection has been started yet"*. A hand-rolled fake has no connection
lifecycle to violate, so every unit test was green. The gate's real SignalR handshake failed on its
first run. The screen is now a permanent gate fixture, so the next screen that mounts too early fails
there too.

**Stated rather than glossed:** roughly fifteen of the new tests were not mechanically shown to fail
against the unfixed code. The ones that decide this item - isolation, the sequence race, dedup,
erasure cascade, the admin label - were, and the isolation pair was re-proven at landing by stripping
all three `site_id` filters from the read store and watching both tests redden.

The item's own open question - *does a message reach anybody offline* - is untouched and still open.