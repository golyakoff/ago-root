# ADR-0151: entitlement is granted by the platform; configuration inside it is the tenant's

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-83`, `23-84`, `23-85`, `23-86`)

## Context

Three separate items reached the same confusion from three directions on one day.

`23-83` found that a tenant-facing route requires a **deployment-wide** provisioning secret, because
`19-03` built a console screen for a tenant to register a module for themselves while `adr/0095` made
turning a module on an assertion by the platform about itself. The model asked a tenant to hold a key
that works against every other tenant.

`23-36` gave a tenant a screen to connect their own Telegram bot, and — checked on 2026-09-07 —
`RegisterChannelCredentialHandler` verifies **only the `channel:manage` permission**. No tier, no
enabled module, no payment. Until that same item, no seeded role held the permission, so nothing could
reach it; now every seeded Admin does. **A dormant hole became a live one on the day the permission was
granted.**

The tier grid (`ago-business` `0012`) prices channels at +100 ₽ each and the AI additions at 300 and
1000, so a capability that turns itself on for free is not a bug in a screen. It is revenue.

The author settled it, 2026-09-07: *«теннант сам себе не включает каналы общения, модули ИИ и FAQ — ему
их включает только система или platform-owner»*, and earlier the same day: *«он может за что-то
заплатить и у него включится, но не сам… его настройки ограничены видами виджета, управлением
операторами, всё в своей песочнице»*.

## Decision

**Two layers, and they never merge.**

1. **Entitlement — may this account use this capability at all.** Granted only by the **platform**: by
   the platform owner acting deliberately (`23-65`), or by the **system** on a payment. Never by the
   tenant, and never as a side effect of the tenant configuring something.
2. **Configuration — what the capability does for this tenant.** The tenant's own, inside their
   sandbox: the widget's appearance, their operators, their own bot token, their own consent text.

**Every capability that appears in the price list has an entitlement**: channels, the AI additions, FAQ,
the calendar. **Every write that would use one checks it**, in the handler and not in the screen.

**A tenant's own credential is configuration, not entitlement.** Pasting a Telegram token is the
tenant's act and stays theirs; it is refused when the account has no channel entitlement, and that
refusal names the reason.

## Why this line and not another

**Because a permission is not an entitlement, and the two are easy to mistake for each other.**
`channel:manage` answers *"is this person allowed to do it on behalf of this account"*. It cannot answer
*"has this account bought it"*, and it never could — permissions are seeded per site by
`RegisterSiteHandler` and have nothing to do with money.

Every place that treated a permission check as sufficient was implicitly asserting that anybody allowed
to act had already paid. That was true only while nobody held the permission.

## Consequences

**Positive.** One rule covers modules, channels, AI and FAQ instead of four negotiations. It also makes
the price list mean something: an option that cannot be turned on without an entitlement cannot be used
without being bought.

**Negative, and named.**

- **Nothing grants an entitlement on payment today.** `22-33` already found the other end of this — a
  lapsed subscription touches no module. So this decision creates a gap it does not close, and `23-86`
  is that gap with a number.
- **Existing tenants may be using capabilities they never bought.** Enforcing an entitlement is a change
  that can take something away from somebody. Whoever builds `23-85` has to establish who is affected
  before switching it on, and taking a paid-for-nothing capability away silently is worse than the hole.
- **A refusal has to be legible.** *"Forbidden"* for an unpaid capability teaches nothing; *"this
  account has no channel entitlement"* is a sentence somebody can act on, and it is the difference
  between a support ticket and a purchase.
- **The console loses screens.** `23-84` removes one; others may follow. That is the intended
  consequence, not collateral damage.
