# the platform owner gives and takes a product from the console

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. `adr/0150` is the decision.
- **Decision**: the author's, 2026-09-07 — *«я как владелец могу с ролью platform-owner выставлять и
  забирать опции теннантам»*. `decisions.md` §6 had already chosen this as the later half of its own
  answer; this is that half.

## What is actually true today, counted on the live deployment

`enabled_modules` holds **zero rows** against **seventeen** sites. Nobody has the calendar, because the
only way to give it to somebody is a hand-made `PUT` carrying a deployment-wide secret
(`module-grant-and-revoke.md`). **A product that cannot be given is not a product.**

## Scope

- **A screen on `/owner`'s tenant detail**: grant a module, revoke one, see what is granted and until
  when, and see whether it is there because we granted it or because the tenant bought it.
- **The browser never holds the provisioning secret.** `Ago.Chat.Api` supplies it from its own
  configuration; the caller is authorised by the platform-owner realm role that already gates every
  owner route (`adr/0150`).
- **`expiresAt` stays a choice, not a default.** The API refuses a body that omits it, deliberately.
  The screen must make "never" something the person picks rather than something they receive — *a grant
  with no expiry is a discount nobody remembers giving.*
- **Revoking a tenant's own purchase keeps `adr/0118`'s asymmetry**: refused unless the request carries
  `force` and a non-blank reason, and the reason is stored verbatim. Taking back what we gave away
  stays easy; taking back what somebody paid for stays deliberate.
- **Every grant and revoke is recorded** — who, when, which tenant, which module, what expiry.

## Where this is likely to go wrong

- **A screen makes a rare act easy, and the runbook's friction was doing work.** It forced a person to
  stop and choose an expiry. The screen has to carry that weight rather than inherit the ease.
- **Provenance is not recoverable after the row is gone.** `/owner` is where a person learns whether
  this was a grant or a purchase, and that distinction decides everything about revoking it. Show it
  before the confirm, not after.
- **The runbook must survive.** It is the path when the console is unavailable, and deleting it because
  a screen exists would be losing the answer for the day the screen does not load.

## Out of scope

- Limits and quantities — `23-66`, which is a different promise and has its own missing half.
- Anything else under *«другие опции теннантов»*. That is a category, not a list; `adr/0150`'s
  consequences say why a screen for a category produces a settings page nobody can explain.

## Done when

- [~] A platform owner grants the calendar to a tenant from the console, and the tenant has it.
      **The mechanism shipped; the end-to-end proof belongs to `23-87`.** Every part of this path is merged and deployed, but the grant could not have succeeded in any deployment: `ModuleProvisioning:Secret` was configured nowhere, so the route answered `503 Module.ProvisioningNotConfigured`. `23-87` configured it and carries the against-the-stand proof as its own Done-when, so the demonstration lives there rather than being claimed twice.
- [x] The provisioning secret never reaches the browser, asserted rather than inspected.
      No contract in `Ago.Chat.Contracts` carries a provisioning secret at all — the browser has nothing to send, which is a stronger property than a test that it is ignored.
- [x] An expiry must be chosen; "never" is a selection and not a default.
- [x] Revoking a purchase still demands `force` and a reason, and the reason is stored.
      `RevokeModuleForSiteAsOwner(… bool Force = false, string? Reason = null)` — a purchased module is refused unless both are supplied.
- [x] Every grant and revoke is recorded and readable afterwards.
      `AccessRecordKind.OwnerModuleGrant` and `OwnerModuleRevoke`, written by the endpoints themselves.
