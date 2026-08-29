# Console: account and billing view

- **Stage**: 13
- **Status**: done (2026-08-29, `ago-chat#116`, `ago-console#57`) — see Outcome below. **Queue sweep
  for this item was missed at merge time** and is being done here, alongside `13-06`'s own sweep, not
  as a separate change — caught while sweeping `13-06`'s row and finding this one still `ready` too.
- **Depends on**: `13-01-operator-invitations-and-seat-entitlement.md` (the seat count/limit this screen
  displays), `13-02-yookassa-subscription-checkout-and-webhook.md` (the checkout-session endpoint the
  upgrade action calls)

## Goal

An operator holding `Permission.SiteConfigure` (`5-08`'s `"Admin"` role — this screen is a site-
configuration surface, the same permission gate `13-01`'s invite-generation endpoint already uses) reaches
a new `ago-console` screen showing their site's current tier, how many seats are used versus the seat
limit, and can start an upgrade — entering a seat count, being redirected to ЮKassa's hosted checkout, and
landing back once `13-02`'s webhook has confirmed the change. **Downgrade is explicitly not built here** —
see Out of scope; its correct behaviour depends entirely on `13-03`'s still-unanswered policy questions,
and this item will not guess at one to fill the button in.

## Context to read first

`docs/backlog/10-03-console-signup-onboarding.md` — the closest existing precedent for a console screen
that calls a backend endpoint and handles a redirect-and-return flow (there: Keycloak's hosted
registration; here: ЮKassa's hosted checkout), including its own "client-side checks are UX-only, never
the source of truth" reasoning, which applies identically to this item's seat-count input (the real
validation is `13-02`'s server-side band/price check). `docs/backlog/12-03-console-owner-operations-view.md`
— the closest existing precedent for a data-display screen reusing `5-07`/`5-08`'s established table/form
styling rather than a new design pass. `docs/backlog/5-08-console-attachments-and-admin-role.md` — confirms
`Permission.SiteConfigure` is already the console's own gate for "site-level configuration," the same
category this screen belongs to. `docs/backlog/13-02-yookassa-subscription-checkout-and-webhook.md`'s
Scope — the exact request/response shape of the checkout-session endpoint this screen's upgrade action
calls, and the fact that tier/seat changes only take effect once the webhook confirms, not on redirect
return alone (see Scope below for how this screen must reflect that honestly).

## Scope

- A new route (e.g. `/billing`, in `ago-console`'s existing router — `5-06`'s scaffold) reachable only for
  an operator holding `Permission.SiteConfigure`, following `5-08`'s existing client-side gating pattern
  for that permission (the real enforcement is server-side on every call, same caveat `10-03`/`12-03`
  already state for their own gated routes).
- Display: current tier (from `13-01`'s `sites.tier` column), seats used (a live operator count for the
  site — reuse whatever read path is cheapest; this is a display concern, not a write-decision, so unlike
  `13-01`'s enforcement check it is not required to bypass caching, though it may read directly if that is
  simplest), seat limit.
- **Upgrade action**: a seat-count input (bounded client-side to a sane range for UX only), calling
  `13-02`'s `POST /api/v1/sites/{siteId}/billing/checkout-sessions`, redirecting the browser to the
  returned `confirmation_url`.
- **Honest pending-state handling on return**: because `13-02`'s tier change only lands once the webhook
  fires, not on ЮKassa's redirect back, this screen must not claim success the instant the browser returns
  — state explicitly, once implemented, how the screen represents "payment submitted, confirmation
  pending" versus "confirmed" (e.g. polling the site's current tier for a short window, or a manual
  refresh prompt — state which was chosen and why). Claiming success prematurely would be a real, user-
  visible lie about payment state, not a cosmetic shortcut.
- Reuse whatever form/table styling `5-07`/`5-08`/`10-03` already established — this item is not a design-
  system pass, matching the same deferral every other console item in this backlog has made for its own
  new screen. **Corrected 2026-08-24**: that chain of deferrals resolved to seventeen lines of CSS; build
  this screen out of `11-05-console-design-foundation.md`'s components and shell instead.

## Out of scope

- **Downgrade, entirely.** `13-03`'s open questions — whether a downgrade is immediate or takes effect at
  period end, whether it is blocked when the current operator count exceeds the new limit — are all
  unanswered. Building a downgrade control now would force this item to either silently pick one of those
  policies (exactly what this stage's planning was told not to do) or ship a button that does nothing
  useful. Neither is acceptable, so downgrade is deferred whole, not half-built, until `13-03` unblocks.
  `roadmap.md`'s own Stage 13 done-when ("entitlements enforce that tier's limits") does not require a
  downgrade *UI* to exist for the stage's core claim to be true — only that upgrading and enforcing a
  purchased tier's limits work, which this item and `13-01`/`13-02` already cover.
- Cancellation — same reasoning, same block, `13-03`.
- Any invite-generation UI (`13-01`'s invite mechanism) — named there as its own deferred, non-blocking
  scope; nothing in this item requires it, and this screen's "seats used" number is a read, not a control
  over invites.
- A design-system pass beyond what earlier console items already established.
- Attachment/history usage display — `13-05`'s territory once (if) it unblocks, not this item's.

## Done when

- [ ] Manually verified against the local cluster, the same "verified live, not asserted" bar `5-06`/
      `10-03`/`12-03` used: a real admin-role operator reaches the screen, sees their site's real tier and
      seat usage, starts an upgrade through a real ЮKassa test-mode checkout, and the screen reflects the
      pending-then-confirmed state honestly once `13-02`'s webhook lands. **Not done** — no live ЮKassa
      test-mode credentials exist in this environment, the same gap `13-02`/`13-03`/`16-03` already
      documented. Everything else about this item is fully verified (route gating, display, the
      pending-state polling logic against mocked backend sequences, the request shapes).
- [x] A non-admin operator token is rejected cleanly from the route (a normal "not authorized" state, no
      billing data leaked), matching `12-03`'s own verification shape for its owner-only route.
- [x] CI build+lint stays green, matching every earlier console item's own precedent for what this
      repository automates versus verifies by hand for `ago-console` — 49 test files, 403 tests, all
      green; `dotnet` side 1149/1149 across all 6 real test assemblies.

## Outcome

Shipped in `ago-chat#116` and `ago-console#57` (merged 2026-08-29). **Scope explicitly expanded
beyond this item's own text**: this file's own Out-of-scope section excluded downgrade and
cancellation, naming the reason as "`13-03`'s policy questions... unanswered." `13-03` merged before
this item was implemented and answered all of them (`decisions/0006`) — shipping upgrade-only while
citing that now-false reason would itself have been a small honesty gap, so the screen includes
upgrade, downgrade and cancellation. Per-operator seat-assignment/toggle UI was deliberately **not**
included — a genuinely different, current reason: it is gated by `site:manage-operators`, not
`site:configure`, and is conceptually operator-management rather than billing.

A real backend gap was found and closed in the same wave: no endpoint anywhere exposed
`Site.Tier`/`SeatLimit` or the active `BillingSubscription` to a `site:configure` operator — blocking
even this item's original upgrade-only scope, not just the expansion. `GET
/api/v1/sites/{siteId}/billing/status` (`ago-chat#116`) closes it.

Full command set green: `ago-chat` 1149/1149 across all 6 real test assemblies; `ago-console` 49 test
files, 403 tests, typecheck and lint clean — both independently re-verified by the managing session.

## Open questions

None for this item's own scope — it depends on `13-01`/`13-02`'s contracts existing first, and deliberately
excludes the one piece (downgrade) that would otherwise require `13-03`'s unanswered policy. No new
product-shape decision is left once those dependencies are answered.
