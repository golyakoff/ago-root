# connecting a channel checks a permission and never an entitlement

- **Stage**: 23
- **Status**: ready — **the three open questions answered by the author, 2026-09-09, recorded below**
- **Depends on**: `adr/0151` is the decision. `23-86` is what makes payment grant one.
- **Found**: 2026-09-07, checked in code after the author settled the rule.

## What is actually true

`RegisterChannelCredentialHandler` checks **`Permission.ChannelManage` and nothing else.** No tier, no
enabled module, no payment, no entitlement of any kind. The same is true of the rotate and revoke paths
beside it.

The tier grid prices a channel at **+100 ₽ a month**. So a tenant on the free tier who holds
`channel:manage` connects Telegram and pays nothing.

## Why this became urgent today rather than at some point

**Until `23-36`, no seeded role held `channel:manage`** — that item found and fixed it, because without
the grant no tenant could ever have connected a channel. It shipped on 2026-09-07.

So the hole existed and was unreachable, and **the fix that made the feature work also made the hole
live.** That is worth stating plainly: this is not a defect somebody missed, it is the second half of a
change that only looked complete.

## Scope

- **Connecting, rotating or revoking a channel credential requires a channel entitlement** for that
  account, checked in the handler.
- **The refusal names the reason.** *"Forbidden"* for an unpaid capability teaches nothing and produces
  a support ticket; *"this account has no channel entitlement"* is a sentence somebody can act on, and
  it is the difference between a ticket and a purchase.
- **The tenant's own token stays theirs.** `adr/0151`'s two layers: the entitlement is the platform's to
  grant, the credential is the tenant's to supply. Nothing here takes the token away from the tenant.
- **The console hides what cannot be used**, but the hiding is not the control — the handler is.

## Three questions, answered by the author, 2026-09-09

**Which entitlement — one per channel kind, or one class-wide?** **One per channel kind.** The
per-channel reading of the price list (*"any one of the available channels, +100 ₽"*) is confirmed as
the decision, not merely the likely commercial intent — the schema should carry a separate
entitlement per channel kind (Telegram, WhatsApp, ...), not one that covers the class.

**Who is already affected, and what happens to them?** They get **disconnected**, and their stored
channel credentials/keys are **cleaned up** — not left dangling in a half-connected state. They can
reconnect later, once entitled. **This is not authorised to switch on silently**: the author wants to
walk through the whole flow end to end, personally, before it runs for real. Treat that walkthrough as
part of Done-when, not a courtesy after the fact.

**Should `23-36`'s live status read stop when the entitlement lapses?** **Yes** — a channel whose
entitlement has lapsed stops being polled, so a non-paying account no longer costs a third party's
rate limit. **This is also a commercial decision, not only a technical one**: the free tier's own
description needs to say connected channels stop working (and their status checks stop) when unpaid,
so the promise made to a free-tier tenant matches what actually happens. Record this in
`ago-business`'s tariff decision doc when this item builds — flagged here so it is not lost between
now and then.

## Where this is likely to go wrong

- **This can take something away from somebody.** Anybody who connected a channel between `23-36`
  shipping and this landing did so legitimately as far as the system told them. Silently breaking a
  working channel is worse than the hole it closes — see the disconnect-and-clean-up answer above, and
  the author's own requested walkthrough before it runs for real.

## Done when

- [ ] Connecting a channel without an entitlement is refused, in the handler, proven by fault injection.
- [ ] The refusal says what is missing rather than only that it is forbidden.
- [ ] A tenant with an entitlement can still supply and rotate their own token.
- [ ] The entitlement is per channel kind, not class-wide, per the author's decision above.
- [ ] Accounts already connected without an entitlement are disconnected and their channel credentials
      cleaned up, reconnectable once entitled — and the author has walked through this flow end to end
      before it runs against real accounts.
- [ ] `23-36`'s live status read stops for a lapsed entitlement, and the free tier's own description in
      `ago-business` is updated to say so in the same change.
