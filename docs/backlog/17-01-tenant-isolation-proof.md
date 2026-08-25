# Tenant isolation: prove it, and make the next handler prove itself

- **Stage**: 17
- **Status**: done — see **Outcome** below. The classification is
  `docs/architecture/tenant-isolation.md`. **The item's own framing was wrong in one respect and it
  matters: the audit's conclusion that "the design is sound, only the proof is missing" did not
  hold.** Implementation found a real cross-tenant hole in `AssignConversationHandler` — read
  *Outcome* before anything else in this file.
- **Depends on**: nothing. Deliberately: this item must not wait behind anything, and it needs no new
  mechanism — the mechanism is already there and mostly right (see Goal).

## Goal

`vision.md`'s loudest claim — "Every piece of data is scoped by `site_id`; this is a multi-tenant
system from day one" — becomes something that can be demonstrated rather than argued, and stays true
without anyone remembering to keep it true. This item is not a redesign. An audit run while scoping
it (2026-08-25, findings below) found the design sound and the enforcement centralized; what is
missing is proof at the composition level and any guard against the thirtieth handler quietly
omitting what the first twenty-nine do.

## What the audit actually found

> **Superseded in one respect — read *Outcome* alongside this.** The claim below that "the design
> [is] sound" did not survive implementation: `AssignConversationHandler` was missing its
> belongs-to-site comparison entirely, and the hole was reachable. The section is kept as written
> rather than edited, because *how* a careful audit missed it is the most useful thing in this file.

Recorded here because it is the reason this item is shaped the way it is, and because a session
picking this up should not have to re-derive it — nor start from the assumption that something is
broken.

**The boundary is centralized, and its core is proven.** Operator-facing tenancy runs through one
port, `IPermissionChecker.HasPermissionAsync(operatorId, siteId, permission)`. Its real Postgres
implementation filters roles by `r.SiteId == siteId`, and
`Ago.Chat.Integration.Tests/PermissionCheckerTests` contains
`HasPermissionAsync_WhenTheRoleIsForADifferentSite_ReturnsFalse` — an integration test against a real
database. That is the load-bearing proof, and it exists.

**Client-supplied `siteId` is a deliberate pattern, not an oversight.** Most operator routes take the
site from a server-derived claim (`ClaimsPrincipalExtensions.GetSiteId()`, populated by
`OperatorIdentityClaimsTransformation`), which makes cross-tenant access impossible by construction —
the caller cannot name another site. But `WidgetConfigEndpoints` and `WebhookEndpoints` both read
`siteId` from the route on purpose, with the reasoning written in the code: "an operator's own site
claim is not necessarily the site being configured". On those routes the entire defence is the
permission check above.

**The gap is in the proof, not the code.** Handler-level tests use `FakePermissionChecker`, so what
they prove is "when the checker says no, the handler returns Forbidden" — a different property from
"an operator of another site is refused". The composition of a route-supplied `siteId` with the real
checker is exercised only where an integration test happens to do it.

**Guards that exist but are untested.** Verified example: `GetWebhookDeliveriesHandler` checks
`endpoint is null || endpoint.SiteId != query.SiteId` and returns NotFound. Its tests cover "endpoint
does not exist" and never the second half of that condition. The code is correct today; nothing would
fail if a refactor dropped it.

**Read models are where a missing filter would be least visible.** `WebhookDeliveryReadStore`'s query
filters by `endpoint_id` alone, with no `site_id` anywhere in the file — safe only because of the
handler check above, which is itself untested. `ConversationReadStore` carries six `select`s and one
mention of `site_id`; each needs its own look, since some are legitimately keyed by something
narrower.

**Nothing is systematic.** Twenty-nine handlers in `Ago.Chat.Application/UseCases`, several of which
are deliberately not tenant-scoped (`CheckCorsOriginHandler`, `GetSiteConfigByPublicKeyHandler`,
`RegisterSiteHandler`, the `Resolve*` consumer-side handlers). There is no written list of which is
which, and no mechanism that notices when a new one joins the wrong group.

## A note on writing this down

Everything above is derivable from the source, which is public. Describing it vaguely here would cost
the reasoning a session needs and protect nothing, so it stays specific — and the real mitigation is
that the item is small enough to close rather than admire (`17-05` carries the general rule this
follows).

## Context to read first

`docs/architecture/authorization.md` — the RBAC model and `adr/0016`. `docs/backlog/0-02-arch-tests.md`
— the precedent this item copies: layering violations fail automatically instead of relying on review,
and that is exactly the shape the guard below needs. `docs/backlog/12-02-cross-tenant-operations-read-
api.md` — the deliberate exception coming next, and the reason this item is urgent rather than
merely worthwhile. `docs/conventions/testing.md` — which level each test belongs at; the point of this
item is that some of these proofs cannot live at the fake-driven unit level.

## Scope

- **A written classification**, checked in, of every use case and every route group: where its `siteId`
  comes from (server-derived claim, or client-supplied), which gate protects it (permission check,
  participant/ownership check, or deliberately none), and why any "deliberately none" is safe. This is
  the artifact — an audit nobody can find later is an audit that will be run again.
- **Cross-tenant tests at the level where the composition is real**, not with a fake: for every route
  that accepts a client-supplied `siteId`, an operator of site B naming site A gets refused. Start with
  `WidgetConfigEndpoints` and `WebhookEndpoints`, the two that exist today.
- **Cover the untested belongs-to-site branches**, starting with the one already found
  (`GetWebhookDeliveriesHandler`), and any sibling the classification turns up.
- **Every read-store query** either filters by `site_id` or carries a one-line note saying which
  narrower key makes it sufficient and which handler check guarantees that key was validated.
- **Visitor-facing paths** proven directly rather than by implication: a visitor token issued for site
  A cannot reach site B's conversation, tested rather than reasoned about from ownership.
- **The guard.** A test in the arch-test spirit: a use case whose command or query carries a `SiteId`
  must call `IPermissionChecker` — or appear in an explicit, commented exemption list. The exemption
  list is the real deliverable: it turns a deliberate exception (`12-02`'s owner-facing cross-tenant
  reader, when it arrives) into a visible, argued entry instead of something indistinguishable from a
  forgotten filter.

## Out of scope

- The rest of Stage 17's security work — secret handling and rotation, dependency and container
  scanning, VPS and cluster hardening, authentication-bypass review, abuse controls beyond `3-05`'s
  rate limits. Each is real; none is this, and bundling them means shipping none properly.
- Redesigning the authorization model. The audit found it sound; this item proves what is there.
- `12-02`'s own cross-tenant reader. This item prepares the exemption mechanism it will need and does
  not build it.
- Row-level security in Postgres, or any database-enforced tenancy. A real alternative design, a real
  argument, and a different item — worth raising only if the classification above turns up something
  the application layer genuinely cannot hold.

## Done when

- [x] Every use case and route group is classified in a checked-in document, with a stated reason for
      each one that is deliberately not tenant-scoped. **`docs/architecture/tenant-isolation.md`** —
      37 use-case entry points (21 RBAC-gated, 16 argued exemptions), 21 tenant-carrying routes and
      hub methods, 5 read-model queries.
- [x] Every route accepting a client-supplied `siteId` has a test where an operator of another site is
      refused, running against a real permission checker rather than a fake.
      **`CrossTenantRouteIsolationTests`** — all six such routes, over real HTTP with a real
      Keycloak-issued token, the real endpoint mappings, the real `RequireOperatorIdentity` policy and
      the real `PermissionChecker`.
- [x] Every belongs-to-site branch has a test that fails if it is removed. Three already had one
      (`RevokeWebhookEndpointHandler`, `DeleteAttachmentHandler`, and the `null` half of
      `GetWebhookDeliveriesHandler`); `17-01` added the two that did not
      (`GetWebhookDeliveriesHandler`'s site half, and `AssignConversationHandler`'s — which did not
      exist as a branch at all, see *Outcome*).
- [x] Every read-store query filters by `site_id` or explains why its narrower key suffices. Five
      queries; two already filtered, three now carry the note in their own remarks and in the
      classification.
- [x] A visitor token from one site provably cannot reach another site's conversation.
      **`CrossTenantConversationAccessTests.AVisitorOfAnotherSite_CannotReadTheConversation`**, with
      the conversation's own visitor reading it successfully in the same test so the refusal is about
      *that* visitor.
- [x] The guard exists and fails when a new tenant-scoped use case skips the check without being
      listed as an exemption — demonstrated by deliberately writing one that does.
      **`TenantScopeTests` + `TenantScopeExemptions` + `Fixtures/TenantScopeRuleFixtures.cs`**: the
      violating handler is checked in permanently next to a compliant twin, and a test asserts the
      rule flags exactly the first.

## Outcome

**A real cross-tenant hole existed and is closed.** `AssignConversationHandler` checked
`conversation:assign` against the site on the caller's own token and then assigned whatever
conversation id it was handed, without ever comparing the two. An operator of site B holding the
ordinary `"Operator"` role could therefore claim any **`Waiting`** conversation of site A by id — and
then passed every downstream check legitimately, because each of them gates on
`conversation.OperatorId == caller` rather than on the site: full message history, sending messages to
that visitor as site A's operator, closing the conversation, downloading its attachments, reading
visitor presence. Site A's own operators could no longer claim it, since it was no longer `Waiting`.

Proven, not reasoned about: run against the pre-fix code, a cross-site claim returned success and the
subsequent history read returned the victim's message body verbatim. Fixed with one
`conversation.SiteId != command.SiteId` comparison in the handler, returning `NotFound` — another
tenant's row must read exactly like one that does not exist. `AnOperatorOfAnotherSite_ClaimsThenReads_AndIsRefusedAtEveryStep`
runs the sequence in order for exactly this reason: a version of the test that skipped the claim would
have passed against the broken code.

**What this corrects in the item's own text.** The audit above concluded "the design [is] sound and
the enforcement centralized; what is missing is proof at the composition level." The first half was
wrong, and the reason it was wrong is instructive rather than embarrassing: the audit looked for
handlers that *skip* `IPermissionChecker`, and this one calls it. Site scoping has two halves — check
the permission for a site, and prove the object belongs to that site — and only the first is
mechanically detectable. The item's proposed guard, taken literally, would not have caught this and
does not catch it today; that limit is stated in the guard's own tests and in
`tenant-isolation.md`.

**The item's guard shape also missed `12-02`.** As specified — "a use case whose command or query
carries a `SiteId` must call `IPermissionChecker`, or appear in an exemption list" — the rule would
never have looked at `ListSitesForOwnerHandler` at all, because it carries no `SiteId`, which is
precisely what makes it cross-tenant. The implemented guard is therefore total in the other direction
as well: *every* entry point is gated or exempt, so an input with no tenant scope is as visible as one
with an unchecked scope.

**What was deliberately left.**

- The systematic alternative — a site-scoped `IConversationRepository.GetByIdAsync(id, siteId)`, so
  every operator-facing load is scoped by construction rather than by a comparison — is named in
  `tenant-isolation.md` and not built. It touches every conversation handler and has no meaning on the
  visitor paths, whose commands carry no site.
- Row-level security in Postgres stays out of scope, as this item said it should. Nothing the
  classification turned up is something the application layer cannot hold.
- The `4-02`/`4-03` assignment claimers are site-scoped by construction (they pick candidate operators
  from the conversation's own site) rather than by a check, and that construction has no test in this
  family. Recorded in `tenant-isolation.md`'s "what this does not prove".

**Suite**: 542 → 556, all green. +4 architecture (the guard), +2 application (the two new
belongs-to-site branches), +8 integration (`CrossTenantRouteIsolationTests`,
`CrossTenantConversationAccessTests`).

## Open questions

None.
