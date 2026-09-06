# the team has one chat of its own, and the tenant is visible in it

- **Stage**: 23
- **Status**: ready
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

- [ ] Operators of one tenant can write to each other and see it arrive without reloading.
- [ ] The owner is visibly the owner.
- [ ] An operator of another tenant cannot read a word of it — asserted the way every other
      tenant-isolation test in this codebase is.
- [ ] `personal-data.md` carries the store, its retention and what erases it.
- [ ] Erasing the site erases the room.

## Open questions

- **Does a message here reach anybody who is offline?** A team chat nobody sees until they log in is
  a noticeboard, which may be exactly right — or may be the reason nobody uses it. Notification is
  not in this item, and whether it needs to be is worth answering before it ships rather than after.
