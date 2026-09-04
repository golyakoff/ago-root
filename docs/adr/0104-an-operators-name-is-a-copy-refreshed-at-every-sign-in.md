# ADR-0104: An operator's name is a copy, refreshed at every sign-in, never a live join to Keycloak

- **Status**: Accepted
- **Date**: 2026-09-04
- **Stage**: 23

## Context

`Ago.Chat.Domain.Operator` has always carried `ExternalSubjectId` and nothing else about the human
behind it — `personal-data.md`'s own row said so: *"`operators`: no name, no email — identity is
joined from Keycloak by subject."* The console already knows its own signed-in user's name
(`operatorDisplayName.ts` reads the ID token's own `profile.name`), because the `openid profile email`
scope is already requested at login. What it cannot show is *anyone else's* name — `/analytics`'s **By
operator** table, `/analytics/conversion`'s second table and `/admin`'s **Assigned operator** column
all render `operatorId.slice(0, 8)`, eight hexadecimal characters, because that is the only thing the
row on the other side of the table has ever carried. This blocks the team screen (`23-22`), the
transfer-target picker, and any report a tenant would actually read as "who did this."

`personal-data.md` carried its own warning against the obvious fix: adding a name column to
`operators` "is not a small change: it converts erasure from a two-place problem into a five-place
one, and it converts an append-only table that is currently retained forever into a personal-data
store that is retained forever." The register's job here is not to overrule that warning silently —
`docs/design/decisions.md` §1 overrules it explicitly, on the record, and this ADR is what makes the
overruling honest by stating exactly what changed and what did not.

Two shapes were on the table for *where the name lives at read time*, and they carry different
failure modes:

- **A live join to Keycloak** on every read that needs a name. Correct by construction — there is no
  copy to go stale — but it is a new synchronous dependency from a product host to the identity
  provider, for reads (a report, an admin list) that today have none. `Ago.Chat.Api`/`Worker` already
  validate Keycloak-issued tokens; neither has ever *called* Keycloak's own API, and `authorization.md`
  is explicit that this codebase already rejected self-issuing credentials specifically to avoid taking
  on more Keycloak-shaped surface than the JWKS validation it already does.
- **A stored copy**, refreshed on some schedule. Cheap to read (an ordinary column, no new I/O on the
  report path), but a copy that never refreshes is the standard argument against denormalising a name
  at all — the objection `docs/design/decisions.md` §1 records finding immediately: *"it goes stale
  when somebody changes their name."*

## Decision

**Store `Operator.DisplayName`/`Operator.Email` as a copy of the validated token's own `name`/`email`
claims, and rewrite both on every sign-in — never query Keycloak from `ago-chat` at read time.**

- **Captured at creation**, in the two places a real human's token produces a new `Operator` row:
  `OperatorInviteRedemptionRepository` (invite redemption) and `RegisterSiteHandler` (bootstrap
  registration). Both already read the token's `sub`; this adds reading `name`/`email` the same way and
  passing them through. `MintDemoTenantHandler`'s minted operator gets neither — that identity is never
  authenticated through Keycloak, so there is nothing to copy, and nothing is invented in its place.
- **Refreshed at sign-in**, at the one point a sign-in is actually observable server-side:
  `GET /api/v1/operators/me` (`GetMyPermissionsHandler`), which the console already calls once per
  session from `PermissionsProvider`. `OperatorIdentityClaimsTransformation` — the thing that actually
  runs on *every* authenticated request — stays a pure read, exactly as `authorization.md` requires of
  it; the refresh does not move into it.
- **The write is a conditional `UPDATE`, not a load-mutate-save through the aggregate**:

  ```sql
  UPDATE operators
  SET display_name = @name, email = @email
  WHERE id = @operatorId
    AND (display_name IS DISTINCT FROM @name OR email IS DISTINCT FROM @email)
  ```

  `IOperatorRepository.RefreshIdentityAsync` issues this directly (the same
  `ExecuteSqlInterpolatedAsync`-through-the-open-connection shape `OperatorCapacityStore` already uses
  for `active_chats`), and returns whether it actually wrote a row. An ordinary session where nothing
  changed costs one statement and zero row writes — `IS DISTINCT FROM`, not `<>`, because an operator
  with no claims to give (the demo tenant's own shape) must not read as "changed" against its own
  `NULL` forever.
- **Nothing in `Ago.Chat.Domain.Operator` can write these two fields.** There is no `SetDisplayName`
  method. The refresh bypasses the aggregate entirely, the identical "no invariant to enforce, so no
  reason to load the aggregate" reasoning `OperatorCapacityStore`'s own compare-and-set already
  establishes for a different column on this same table.
- **No denormalised second copy anywhere.** `OperatorAnalyticsReadStore`, `ConversionReportReadStore`
  and `ConversationReadStore`'s admin list all `LEFT JOIN operators` at read time; none of them store a
  name. This is what keeps the erasure count at one place rather than five — see
  `personal-data.md`'s own `operators` row and its "two-place problem" note for the accounting.

## Consequences

**Positive.** Every screen that names an operator now names a person, with no new runtime dependency:
`Ago.Chat.Api`/`Worker` still never call Keycloak's own API, only validate tokens issued by it, exactly
as before. The staleness the rejected alternative worried about is bounded to "since this operator's
last sign-in" rather than open-ended, and the conditional `UPDATE` means the steady-state cost of that
bound is one no-op statement per session, not a row rewrite. `personal-data.md`'s own erasure count
stays honest because nothing was denormalised past the one row.

**Negative.** A name changed in Keycloak is wrong everywhere in this product until that operator next
calls `GET /api/v1/operators/me` — which in practice means until their next login, since that is the
only caller. An operator who changes their name and never signs in again keeps showing the old one
forever. This is the trade the "why the refresh" note in `docs/design/decisions.md` §1 names directly:
it costs a few lines and removes the only serious objection to storing a copy at all, but it does not
remove staleness, only bound it.

**A new personal-data field, on the record.** `personal-data.md`'s `operators` row now states what
reaches it, that it is a copy rather than a join, and that `16-02`'s existing site-erasure cascade
reaches it for free (`SiteErasureQuery.DeleteSiteAsync`'s own remarks already list `operators` among
the tables its `delete from sites` reaches — verified by reading that code, not assumed). No new
erasure surface was built and none was needed: two more nullable columns on an already-cascading row
add nothing a site erasure was not already going to remove.

**No avatar, still.** `personal-data.md` already records the author's own decision against one — an
image is a further category of personal data plus an upload/moderation surface, for a benefit a
name and initials already provide. This item does not reopen that.

## Alternatives considered

- **Query Keycloak live from `ago-chat` on every read that needs a name.** Rejected in
  `docs/design/decisions.md` §1 directly: a new synchronous dependency from a product host to the
  identity provider, for a problem this system does not have — every other identity fact this codebase
  needs is already resolved once, from a validated token, never fetched.
- **Refresh from a background job polling Keycloak's admin API.** Considered and rejected for being
  strictly worse than sign-in-triggered refresh on every axis that matters here: it still needs the
  synchronous-dependency machinery the first alternative was rejected for (an admin-API client, a
  credential for it, a retry/backoff story), on a schedule that cannot beat "the next time this person
  actually uses the product" for freshness, while adding a second write path to the same two columns
  that the sign-in refresh does not need.
- **Leave `operators` anonymous and build the team screen around ids.** Named and rejected in
  `docs/design/decisions.md` §1: it makes "manage your team" unsellable, and blocks `23-17`/`23-18`/
  `23-22` for no compensating benefit — a report a reader cannot attribute to a person is not a report
  a tenant keeps reading.
- **A materialised, denormalised copy of the name on each read model** (`operator_analytics` carrying
  its own `operator_name` column, refreshed by an outbox consumer). Rejected: it would have been the
  five-place erasure problem `personal-data.md`'s own warning named, for a benefit an ordinary `JOIN`
  already provides at the query volumes these reports run at (`IOperatorAnalyticsReadStore`'s own
  remarks: "pure observability for a human reading a panel... at human frequency").
