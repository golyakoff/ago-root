# connecting a channel checks a permission and never an entitlement

- **Stage**: 23
- **Status**: ready
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

## Where this is likely to go wrong

- **This can take something away from somebody.** Anybody who connected a channel between `23-36`
  shipping and this landing did so legitimately as far as the system told them. **Establish who is
  affected before switching it on**, and decide deliberately whether they keep it. Silently breaking a
  working channel is worse than the hole it closes.
- **Which entitlement?** One per channel kind, or one that covers channels as a class? The price list
  says *"any one of the available channels, +100 ₽"*, which reads as per-channel — but that is a
  commercial reading of a sentence, not a decision, and it should be confirmed before a schema carries
  it.
- **`23-36`'s live status read** asks the provider on every page load. A channel whose entitlement has
  lapsed should stop being asked about, or we pay a third party's rate limit for an account that is not
  paying us.

## Done when

- [ ] Connecting a channel without an entitlement is refused, in the handler, proven by fault injection.
- [ ] The refusal says what is missing rather than only that it is forbidden.
- [ ] A tenant with an entitlement can still supply and rotate their own token.
- [ ] Who is already affected is established and the decision about them is written down.
