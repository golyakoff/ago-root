# the tenant can see and manage who works here

- **Stage**: 23
- **Status**: done (2026-09-05). `/settings/operators` in `ago-console`, gated on
  `site:manage_operators`; a new `ago-chat` read (`GetOperatorTeamHandler`,
  `GET /api/v1/sites/{siteId}/operators`) supplies the named rows the existing
  `seat-assignment-summary` endpoint never carried. Invite, seat toggle and removal all reuse `13-01`/
  `13-03`'s existing write endpoints unchanged. Two real gaps found and left open, not silently
  folded in: no role picker (unchanged, per Out of scope) and no console surface for *redeeming* an
  invite at all — see `ui-inventory.md`'s corrections section.
- **Depends on**: `23-02` — rows a tenant can recognise; a team screen listing eight hex characters
  is not a team screen. `23-21`/`23-24` — the shared `AccessRefusal` treatment (`23-24` generalised
  `23-21`'s calendar-specific one to every dedicated-permission gate, this screen's included) for a
  person without `site:manage_operators`, so this screen does not add another hand-written refusal.
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

- [x] A tenant holding `site:manage_operators` reaches the screen, sees every operator by name, and
      sees which hold seats. (A new read was needed for this — `GetSeatAssignmentSummaryHandler`
      alone carries no per-operator rows; see the report.)
- [x] An operator without that permission gets `23-24`'s generalised `AccessRefusal` treatment
      (`23-21`'s own shape, since consolidated), not a blank screen.
- [x] Inviting when the seat limit is already reached is refused *before* the invite is created, and
      says so in the tenant's own words. Predicted from the team list's own row count, not
      `heldSeats` — the two are different numbers (`OperatorsTeamPage`'s own doc comment).
- [x] Removing an operator releases their conversations back to `Waiting` — `13-03`'s existing
      behaviour, asserted from the screen's own flow (and from a real mutation of the release
      mechanism against the live Postgres/RabbitMQ pipeline, in this item's own fails-before table).
- [x] A site above its seat limit after a downgrade renders every operator and says which are over.
- [x] A tenant cannot see or act on another tenant's operators (server-side `SiteId` scoping,
      integration-tested).
- [x] `ui-inventory.md` §13.4's finding is answered in the corrections section.

## Open questions

None.

## Outcome

**The console's first check of `site:manage_operators`.** The permission has existed since `5-08`; until
this item nothing in the console read it, so a tenant holding it had no screen that behaved differently
from one who did not. The nav entry follows `23-21`/`23-24`'s established shape — always drawn, muted
when the caller lacks the grant — rather than vanishing, which is `decisions.md` §10's rule.

**A wrong premise in the original finding, corrected rather than carried forward.** `ui-inventory.md`
§13.4 assumed `13-03`'s `seat-assignment-summary` endpoint already returned per-operator rows and only
the screen was missing. It never did. The item needed a new read (`GetOperatorTeamHandler`), and the
correction is written into the inventory beside the finding instead of the finding being quietly
deleted — a finding that turns out to be half wrong is worth keeping with its correction attached.

**What `personal-data.md` gains is a note about audience, not about storage.** `OperatorTeamReadStore`
is a plain `select` against `operators` — no copy, no new column. But it is the first read whose
*entire purpose* is showing a colleague's name and email, to somebody holding `site:manage_operators`
specifically, rather than incidentally as a byline on a report. It does not widen who can learn a
name; it is named because a rule only ever applied to incidental exposure stops being applied the
first time exposure is the point.

**Landed hours after the code, and one gap survived the delay.** This half sat written and uncommitted
in two worktrees — an original and a rebuilt twin, byte-identical — until `queue-audit.sh`'s worktree
check listed them. Applying the recovered diff needed two hand corrections: `personal-data.md` had
moved under it (three rows added the same day), and **the nav table had no row for `/settings/operators`
at all** — the screen this item shipped was in `consoleNav.ts` and missing from the inventory that
claims to describe it. Neither was in the recovered diff. Moving a diff across bases is not the same as
moving a true statement, for the third time today.
