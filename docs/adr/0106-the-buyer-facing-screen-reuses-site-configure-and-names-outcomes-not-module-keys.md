# ADR-0106: The buyer-facing products screen reuses `site:configure`, and its copy names outcomes, never module keys

- **Status**: Accepted
- **Date**: 2026-09-05
- **Stage**: 23

## Context

`23-25` builds `/settings/products` in `ago-console` - "what else AGO does", on a surface addressed
to the person who can buy it (`docs/design/decisions.md` §10, the *navigation is not a sales surface*
half). Two questions had no existing answer to reuse.

**Who may see it.** The backlog item's own brief: "gate it on the permission an owner holds, not on
being any operator." `Ago.Chat.Domain.Permission` has no member named anything like `site:own` or
`tenant:buy` - the closest existing concept is `SiteConfigure` ("site:configure"), which already
gates `/settings/billing` end to end (`BillingPage.BILLING_PERMISSION`, checked server-side by
`CreateCheckoutSessionHandler`/`ChangeSubscriptionSeatsHandler`/`CancelSubscriptionHandler`) - the one
screen in this console that already asks "may this identity spend the tenant's money."

**What to list, and how to describe it.** `23-21` put this workspace's enabled module keys
(`"calendar"`, `"faq"`, …) on `GET /api/v1/operators/me`. The backlog item's own instruction: "Write
about what the product does, not about our schema. `calendar` is a word from our database. *Taking
bookings* is the thing being sold." Nothing before this decided how literally to take that for a
brand-new screen with no existing copy to follow, or which products belong on it at all - AGO Chat,
AGO Calendar and the FAQ module are not the platform's only in-flight surface; AGO Inbox (channel
connections - Telegram, WhatsApp, …) is real and shipped (`docs/roadmap.md` Stage 14) but has no
console screen and no equivalent single tenant-held fact on `operators/me`.

## Decision

**1. `Permission.SiteConfigure` is this screen's gate, reused rather than a new permission invented.**
The alternative - a dedicated `site:own` permission naming the buyer explicitly - was rejected: no
caller anywhere in `Ago.Chat.*` needs to distinguish "may configure this site" from "may act as its
owner" today (`Permission.cs`'s own catalogue has no such split for any of `SiteErase`/`SiteExport`/
billing), and inventing one permission for one screen with no second caller is exactly the kind of
speculative permission `authorization.md`'s "more permissions arrive with their first real caller"
rule warns against. `site:configure` is already the permission this console treats as "may act for
the tenant as a whole" - `/settings/billing`'s own checkout is the strongest existing precedent, and
`ProductsPage` reuses `BillingPage`'s exact gate-and-refusal shape (a danger `Alert` plus a link back
to the queue) rather than a new one.

**2. The product list is a fixed set the console names by outcome, never by module key - three rows
today: the base conversation product (always held), booking (`enabledModules.includes("calendar")`),
and automatic answers (`enabledModules.includes("faq")`).** `buildRows` in `ProductsPage.tsx` is the
one place either raw key string is read; every string a reader sees names what the product does for
their customers ("Let customers book an appointment…", never "Calendar" or "FAQ"). This extends the
backlog item's own instruction past the description column to the action-link labels as well - "Open
your booking queue", not "Open Calendar" - on the reasoning that a next-step link naming the schema
word would leak exactly what the description column was written to avoid.

**3. AGO Inbox's channels are not a row on this screen, named here as a deliberate omission rather
than left silent.** A connected channel is a `ChannelCredential` row, not an `EnabledModule` entry -
there is no single tenant-held boolean for "this workspace has AGO Inbox" the way `enabledModules`
gives one for calendar/FAQ, and the console has no screen for channels at all yet. Representing that
honestly would need a new server read, which `23-25`'s own scope says to stop and report rather than
absorb.

## Consequences

- **A future dedicated "site owner" permission, if one is ever built, has to decide whether this
  screen's gate moves onto it.** Today an operator holding `site:configure` for reasons unrelated to
  billing (a supervisor trusted with widget/FAQ/tag configuration but not spending authority) also
  sees this screen. That is the same blast radius Billing already accepted for the identical
  permission, not a new one this item introduces.
- **A fourth product added later must follow the same two rules** - its "held" fact must already be
  answerable from an existing response (or this decision's own scope note applies again), and its
  copy must name what it does, not its key. `buildRows`' own doc comment states both, so the next
  row is a template to extend, not a pattern to rediscover.
- **AGO Inbox stays invisible on the one screen built to be honest about what a tenant could buy**,
  until a channel-held fact exists somewhere a client can read. That gap is now recorded rather than
  merely absent.

## Alternatives considered

- **A new `site:own`/`tenant:buy` permission.** Rejected in Decision 1's own reasoning - no second
  caller, and `authorization.md`'s stated policy against permissions with none.
- **Gate on realm-role/platform-owner status instead of an operator permission.** Rejected: the
  platform owner (`/owner`) is a different audience answering a different question (`ui-inventory.md`
  §8.1: "cross-tenant platform operations"), and this screen is scoped to one tenant's own buyer, the
  same distinction `decisions.md` §10 draws between "a colleague at this tenant" and "the platform
  owner."
- **Show the raw module key with a human-readable label beside it** (e.g. "Calendar (`calendar`)").
  Rejected: the backlog item is explicit that showing the schema word at all is the failure mode, not
  showing it *unexplained*.
- **Represent AGO Inbox with a guessed or hardcoded "not held" row.** Rejected: a row this screen
  cannot honestly mark held or not held (no server fact backs either state) would be worse than no
  row, on the same "a fact-shaped thing resting on an assumption it cannot check" reasoning
  `decisions.md` §7 already applies to invented valuation numbers.
