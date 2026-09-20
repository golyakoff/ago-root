# 25-189 · The public demo's shared operator login has no seat

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-20, the managing session, trying to log into `office.reserve-me.ru` as
  `demo-operator` to live-verify `25-158`/`25-159` (both landed and deployed, needing a real
  console session to drive the repro).

## What is actually true today

`demo-shop1.reserve-me.ru`'s own landing page advertises a public, intentionally-shared login —
`demo-operator` / `demo-operator-password` — as giving "access only to the Demo Shop One tenant."
Logging in with it right now does not reach the operator dashboard at all: Keycloak correctly
authenticates the account (the console's own header shows "Demo Operator"), but the console then
renders the **first-run "complete your site setup" onboarding screen** - the one a brand-new,
site-less owner sees - rather than Demo Shop One's conversation queue.

Confirmed directly against the live database (`ago_chat` on the demo cluster's `postgres` pod):

- The site binding is intact - `operators` has a `Demo Operator` row
  (`id=00000000-0000-0000-0000-000000000002`) with `site_id` pointing at the seeded "Demo Shop
  One" site (`00000000-0000-0000-0000-000000000001`), not removed, with the exact
  `external_subject_id` the realm fixture gives that Keycloak user.
- Its `operator_roles` row for that site's `Operator` role has **`holds_seat = false`**:

  ```
             operator_id              |               role_id                | granted_at | holds_seat
  --------------------------------------+--------------------------------------+------------+------------
   00000000-0000-0000-0000-000000000002 | 00000000-0000-0000-0000-000000000003 | -infinity  | f
  ```

  while two *other* operators on the same site's roles already hold seats - one seeded
  (`00000000-...-0006`, Operator) and one real, non-placeholder account
  (`35fed5eb-5f72-40b7-9384-1b84714b5489`, holding both the Admin and Operator seats).
- `granted_at = -infinity` on every row for this site (not just the demo operator's) is the
  backfill sentinel `25-170`'s migration writes for a role that predates the
  `operator_roles.holds_seat`/`granted_at` columns - consistent with this being the seat state the
  migration carried forward from whatever `operators.holds_seat` already said, not something the
  migration itself changed.

So this is very likely an ordinary seat-limit reconciliation outcome - `Demo Shop One`'s own
operator-seat limit is small, a real account (`35fed5eb-...`) already holds one of the seats, and
`demo-operator`'s own seat lost out - rather than a bug in `25-170`'s migration or in `25-181`'s
new capacity gate. **Root cause not fully traced past this point**: which mechanism demoted
`demo-operator` specifically (`OperatorRoleSeatReconciler`/`EntitlementWatchdogJob`, per this
session's own recent work on `25-181`) and when, is not yet confirmed - only the resulting DB state
is.

## Why this matters

`demo-shop1.reserve-me.ru`'s own "ПОПРОБОВАТЬ ВЖИВУЮ" (try it live) call-to-action tells a real
visitor to open the widget, send a message, then open the console with this exact published login
and reply to themselves. **That flow is broken for any visitor trying it right now** - the second
half of the demo's own headline pitch does not work. This is a production defect on the live
marketing surface, not a queue/documentation gap.

It also blocked this session's attempt to live-verify `25-158`/`25-159` (a rich-form link
rendering as clickable, and a widget consent choice actually resolving) - both fixes are confirmed
deployed, but neither could be driven end-to-end through the real console with this login.

## Scope

- Confirm the actual demotion mechanism and moment (read `OperatorRoleSeatReconciler`'s/
  `EntitlementWatchdogJob`'s own logic against this exact state, check whichever audit trail these
  seat changes leave, if any).
- Decide the right fix: grant `Demo Shop One` an extra Operator seat via `25-181`'s own new owner
  seat-grant mechanism (the fast, no-code path now that it exists), raise the site's own seat
  limit, or free a seat by removing whichever operator should not be occupying one on a public demo
  tenant.
- Whatever the fix, prove it live: log in as `demo-operator` again afterward and confirm the
  console reaches Demo Shop One's conversation queue rather than the onboarding screen.

## Out of scope

- Re-litigating `25-181`'s own capacity gate - it is working as designed; this item is about which
  seats a real public demo tenant should have and who holds them, not the mechanism enforcing the
  limit.
- `25-158`/`25-159`'s own live-verification Done-when boxes - tracked on those items, to be
  attempted again once this is fixed.

## Done when

- [ ] The reason `demo-operator` lost its seat is identified (not just observed).
- [ ] `demo-operator` holds an Operator seat on Demo Shop One again, proven by logging in and
      reaching the conversation queue rather than the site-setup screen.
- [ ] The fix is one that will not silently repeat - either the site's seat allocation now has
      headroom for the published shared login specifically, or whatever consumed the seat has an
      owner who knows not to.
