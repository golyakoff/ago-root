# an operator has a name, and the product uses it

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing
- **Decision**: `docs/design/decisions.md` §1

## Goal

Every screen that names an operator names a person. Today `Ago.Chat.Domain.Operator` carries
`ExternalSubjectId` and nothing else about the human — verified: the type has `Id`, `SiteId`,
`Status`, `Capacity`, `ExternalSubjectId`, `HoldsSeat`, `RemovedAt`, and no name and no email. So
`/analytics`'s **By operator** table, `/analytics/conversion`'s second table and `/admin`'s
**Assigned operator** column render `operatorId.slice(0, 8)` — eight hexadecimal characters
(`ui-inventory.md` §5.1, §5.2, §12.9). The reader cannot tell who that is.

After this, the `operators` row carries a display name and an email, captured from the token's claims
at invite redemption and **rewritten at every sign-in**, and the reports render it.

## Context to read first

- `docs/design/decisions.md` §1 — including *why the refresh*, which is the part an implementation
  tends to drop
- `docs/design/flows.md` 2.4 and 4.4; `docs/design/ui-inventory.md` §5.1, §5.2, §12.9
- **`docs/architecture/personal-data.md`, and specifically its own warning against this change**:
  *"A change that adds a name column to `operators` … is not a small change: it converts erasure from
  a two-place problem into a five-place one."* §1 overrules it, and the item's job is to make the
  overruling honest — the register gains the row in the same change, and `16-02`'s cascade is
  asserted rather than assumed
- `docs/architecture/authorization.md` — `adr/0022`, how a Keycloak `sub` becomes an `OperatorId`
- `docs/adr/0068-*` — one login, several tenancies: a name is per-identity, a row is per-tenancy
- `Ago.Calendar.Domain/Operator.cs` — the *other* product's operator row already holds a display name
  and an `invited_email`; the two tables are deliberately not the same shape and this item does not
  make them one

## Scope

- `Operator.DisplayName` and `Operator.Email`, optional at construction the way
  `ExternalSubjectId` already is, so existing `new Operator(...)` call sites keep compiling. One
  additive migration on `operators`.
- **Capture at redemption.** `OperatorInviteRedemptionRepository` /
  `RedeemOperatorInviteHandler` — the one path that creates an operator from a real human's token.
  `RegisterSiteHandler` and `MintDemoTenantHandler` create operators too and must pass whatever they
  have; the demo tenant has no claims, so leave it empty rather than inventing one.
- **Refresh at sign-in.** `OperatorIdentityClaimsTransformation` runs
  `ResolveOperatorIdentityHandler` once per authenticated request; it is a *read* and must stay one.
  Write the refresh where a sign-in is actually observable — `GET /api/v1/operators/me`
  (`OperatorsEndpoints`), which the console calls once per session from `PermissionsProvider` — as a
  conditional `UPDATE ... WHERE display_name IS DISTINCT FROM @name OR email IS DISTINCT FROM @email`,
  so a request that changes nothing costs one statement and no row write.
- `GET /api/v1/operators/me` carries the caller's own name.
- The read models: `IOperatorAnalyticsReadStore`'s per-operator buckets, `IConversionReportReadStore`'s
  per-operator rows, and `/admin`'s conversation list gain the name.
- `ago-console`: the two identical local `operatorLabel` helpers in `OperatorAnalyticsPage.tsx` and
  `ConversionReportPage.tsx`, and `AdminConversationsPage.tsx`, render the name with the id as the
  fallback for a row that predates the column.
- `personal-data.md` gains the `operators.display_name` / `operators.email` row: what it is, that it
  is a copy refreshed from the IdP, and which existing cascade removes it.

## Out of scope

- **Querying Keycloak from `ago-chat`.** Explicitly rejected in §1: a new synchronous dependency from
  a product host to the identity provider for a problem this does not have.
- An avatar. `personal-data.md` records the author's own decision against one.
- The team screen — `23-22`, which depends on this.
- Naming a *visitor*. A visitor has no name to know.

## Done when

- [x] An operator redeeming an invite ends with `display_name` and `email` on their row, asserted by
      an integration test against a token carrying `name`/`email` claims —
      `OperatorInviteEndpointTests.Redeem_ARealTokenCarryingNameAndEmailClaims_EndsWithBothOnTheOperatorRow`.
- [x] Changing the name in the IdP and signing in again updates the row — a test calling
      `GET /api/v1/operators/me` twice with two different `name` claims, asserting one row and two
      values — `OperatorIdentityRefreshEndpointTests.GetMe_CalledTwiceWithDifferentNameClaims_UpdatesTheSameRowToTheSecondValue`.
- [x] A second call with unchanged claims writes no row, asserted on the command rather than by eye —
      `OperatorIdentityRefreshTests.RefreshIdentityAsync_ASecondCallWithUnchangedClaims_WritesNoRow_AndReturnsFalse`,
      against `OperatorRepository.RefreshIdentityAsync`'s own boolean return value.
- [x] `/analytics`, `/analytics/conversion` and `/admin` render a name where they rendered eight hex
      characters, and still render the id for a row that has no name — proven in `ago-console`'s own
      `OperatorAnalyticsPage.test.tsx`/`ConversionReportPage.test.tsx`/`AdminConversationsPage.test.tsx`.
- [x] `personal-data.md` carries the new row and states which cascade removes it.
- [x] `ago-console`'s ux-gate screenshots regenerate without a diff that hides an untranslated string —
      `npm run ux-gate`, 37 passed (5 skipped, unrelated desktop-viewport duplicates of a mobile-only
      suite).

## Open questions

None.
