# the tenant can see and manage who works here

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-02` — rows a tenant can recognise; a team screen listing eight hex characters
  is not a team screen. `23-21` — what a person without `site:manage_operators` sees, so this screen
  does not add another hand-written refusal.
- **Decision**: `docs/design/decisions.md` §1 is what makes this possible; the need is
  `docs/design/flows.md` 4.3

## Goal

A tenant can invite a colleague, see who is on the site, see who occupies a paid seat, and remove
somebody who has left — from the console, in one place.

The backend shipped in `13-01` and `13-03`. **The console has no route, no nav entry and no screen**
for any of it, and never checks `site:manage-operators` at all (`ui-inventory.md` §13.4).
`/settings/billing` shows "Seats used" and "Seat limit" as two numbers with no way to see or change
who occupies them. `flows.md` 4.3 was filed as `built` on the strength of the backend and corrected
on 2026-09-04 — the capability is built and the tenant cannot reach it.

## Context to read first

- `docs/design/flows.md` 4.3 in full — including *"the recurring failure is that permissions are
  shown as capabilities and understood as job titles"*
- `docs/design/ui-inventory.md` §13.4, §6.7 (billing's two numbers), §1 (the permission vocabulary
  the console checks, and the one it does not)
- `docs/backlog/13-01-*` and `docs/backlog/13-03-*` — invitations, seats, removal, and the
  `holds_seat`/`removed_at` model on `Operator`
- `docs/architecture/data-model.md` — the over-seats condition is a derived read, never a stored
  column, and the seat-limit check is a `SELECT ... FOR UPDATE` on `sites`
- `docs/architecture/authorization.md` — `Permission.SiteManageOperators`

## Scope

- A console route and nav entry gated on `site:manage_operators` — a permission the console checks
  for the first time.
- The list: `GET /api/v1/sites/{siteId}/operators/seat-assignment-summary`
  (`GetSeatAssignmentSummaryHandler`) already exists and the console has never called it. With
  `23-02` its rows carry names.
- Invite: `OperatorInviteEndpoints` / `CreateOperatorInviteHandler` already exist. The screen shows
  what an invite costs against the seat limit **before** it is sent, because `13-01`'s seat check
  refuses at redemption and a refusal the inviter never saw coming is a bad moment for two people.
- Seat toggle and removal: `POST .../operators/{id}/seat` and `POST .../operators/{id}/remove`
  already exist. Removal is destructive and gets the `Dialog`-confirmed treatment the product uses
  for its other destructive acts — not the third confirmation shape `ui-inventory.md` §12.3 records
  for the calendar's worker delete.
- **Removal's real consequence, said on the screen**: `Operator.Remove` raises `OperatorRemoved`, and
  `OperatorConversationReleaser` releases that operator's assigned conversations back to `Waiting`.
  Somebody removing a colleague mid-shift should know that before clicking, not after.
- The over-seats case is a derived read and is rendered honestly: `13-03` allows a site to sit above
  its seat limit after a downgrade, and the screen must show that rather than hiding a row.

## Out of scope

- **Re-roling.** There is no write for it: `CreateOperatorInviteHandler` sets an invitee's roles at
  invite time and nothing changes them afterwards. Adding one is a second promise with its own
  question attached, so it is deliberately not folded in — see the stage report.
- Job-shaped role names. `flows.md` 4.3's *"must not be made to learn an eleven-permission vocabulary
  to add a receptionist"* needs a role catalogue that does not exist.
- Anything about billing beyond the seat numbers this screen already needs. `/settings/billing` keeps
  owning the subscription.
- The platform owner's cross-tenant view of operators. Different actor, different item.

## Done when

- [ ] A tenant holding `site:manage_operators` reaches the screen, sees every operator by name, and
      sees which hold seats.
- [ ] An operator without that permission gets `23-21`'s treatment, not a blank screen.
- [ ] Inviting when the seat limit is already reached is refused *before* the invite is created, and
      says so in the tenant's own words.
- [ ] Removing an operator releases their conversations back to `Waiting` — `13-03`'s existing
      behaviour, asserted from the screen's own flow.
- [ ] A site above its seat limit after a downgrade renders every operator and says which are over.
- [ ] A tenant cannot see or act on another tenant's operators.
- [ ] `ui-inventory.md` §13.4's finding is answered in the corrections section.

## Open questions

None.
