# connecting a channel checks a permission and never an entitlement

- **Stage**: 23
- **Status**: done, one box gated on the author — **the three open questions answered by the author,
  2026-09-09, recorded below**. Code independently reviewed, verified and merged — `ago-chat#284`,
  `ago-console#223`. Five of six Done-when boxes are genuinely closed; the sixth is deliberately left
  open rather than ticked or filed as a separate item, because it is not further work but a specific,
  one-time act (walking the real disconnect flow against real accounts) that only the author may
  perform, per the safeguard this item's own answers established — see the note above Done-when.
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

## Implementation note, worker session, 2026-09-14, independently verified and merged the same night

Built in a background-worker session, then independently re-verified by the managing session (its own
`dotnet build`/`test` and `npm` runs, not just the worker's own claim) and merged: `ago-chat#284`
(3280/3280 tests), `ago-console#223` (1370/1370 tests).

- The permission-then-entitlement check landed in `RegisterChannelCredentialHandler`,
  `RevokeChannelCredentialHandler` and `GetChannelCredentialStatusHandler` (`ago-chat`,
  `Ago.Chat.Application`), reusing `23-86`'s own `IBillingOptionEntitlementProvider`/
  `IModuleQuantityGrantStore` pair rather than a new mechanism — a new `ChannelKind` →
  `BillingOptionKey` mapping (`ChannelEntitlementOptionKeys`, Domain) is the only new resolution step,
  since the price list is already one entitlement per option and the existing config shape already
  reads by opaque key.
- **The disconnect/cleanup mechanism is built and fully tested against fakes, and deliberately wired to
  run only when a platform owner calls it** — two new owner-only HTTP routes
  (`GET /api/v1/owner/channel-entitlements/non-entitled-credentials` to list, then
  `POST .../disconnect` naming the exact reviewed ids). Nothing calls either route automatically: no
  startup hook, no recurring job, no migration. See the worker's own report for the full reasoning and
  the explicit confirmation that nothing was run against real data.
- `ago-business`'s tariff doc (`docs/decisions/0012-*.md`, section 7) already stated the free-tier
  consequence and the "credentials deleted, not just marked inactive" shape, written by the author on
  2026-09-09 when the three questions above were answered — verified against what was actually built;
  no `ago-business` change was needed.
- `ago-console` needed no production code change: the existing generic problem-details rendering
  already surfaces a handler's refusal text verbatim, so `TelegramChannelPage` already shows *why* a
  channel can't be connected the moment the server names it. A regression test was added
  (`TelegramChannelPage.test.tsx`, "not entitled" describe block) to prove this rather than assert it.
- The tension in applying the entitlement gate to *revoke* (see item text below) was implemented
  literally, per instruction, and flagged rather than resolved unilaterally — the author's call.

## Done when

- [x] Connecting a channel without an entitlement is refused, in the handler, proven by fault injection.
      — `RegisterChannelCredentialHandler`/`RevokeChannelCredentialHandler`; the check was temporarily
      neutralized, the new refusal tests shown red, then restored and shown green (`ago-chat#284`).
- [x] The refusal says what is missing rather than only that it is forbidden. — `ChannelEntitlement.Refusal`
      names the channel kind: "this account has no channel entitlement for {kind} channels."
- [x] A tenant with an entitlement can still supply and rotate their own token. — the existing
      success-path tests (e.g. `HandleAsync_WhenPermitted_RegistersAnActiveCredential`) exercise the
      entitled path and pass; the entitlement check adds a gate, not a new obstacle for a paying tenant.
- [x] The entitlement is per channel kind, not class-wide, per the author's decision above. —
      `ChannelEntitlementOptionKeys.For(ChannelKind)`, one `BillingOptionKey` per kind, a `switch` that
      fails to compile on an unhandled new kind rather than deriving a plausible-looking key silently.
- [~] Accounts already connected without an entitlement are disconnected and their channel credentials
      cleaned up, reconnectable once entitled — and the author has walked through this flow end to end
      before it runs against real accounts. **Left open on purpose, per the note below**: the tool
      exists (owner-only, two-step: list, then disconnect the exact reviewed ids —
      `GET`/`POST /api/v1/owner/channel-entitlements/...`) and is fully tested against fakes, but
      nothing has run it against real accounts, and nothing may until the author does so personally.
- [x] `23-36`'s live status read stops for a lapsed entitlement, and the free tier's own description in
      `ago-business` is updated to say so in the same change. — `GetChannelCredentialStatusHandler`
      gated the same way; `ago-business`'s `docs/decisions/0012-*.md` section 7 already stated this
      consequence in the author's own words from 2026-09-09, verified against what was actually built.

**One box left open on purpose.** The item is not `done` until the author has run the disconnect
walkthrough — this is not a formality: it is the specific safeguard the author asked for, and closing
the item without it would be the exact "switch on silently" outcome that safeguard exists to prevent.
