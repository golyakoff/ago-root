# ADR-0146: A tenant's own "who accepted" screen omits the client IP and user agent the record also holds

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23

## Context

`24-01` gave `AcceptanceRecord` two narrow request-context fields beyond who/what/when -
`ClientIp`/`UserAgent` - kept, in that item's own words, because "a consent record is commonly
indefensible without them", and deliberately narrower than a surveillance log (no referrer, no
session id, no device fingerprint). `23-37` is the first screen that reads this table back for a
tenant: `GET /api/v1/sites/{siteId}/consent-documents/{purpose}/acceptances` answers "which version
did this person accept, and when" - the exact question `24-02`'s own Goal names.

That read could trivially also hand back `ClientIp`/`UserAgent`, since the row already holds them.
Whether it should is a real question this item was not asked to answer implicitly by shipping a
response shape, so it is decided here instead.

`docs/architecture/personal-data.md` already draws the relevant distinction elsewhere in this system:
an IP address is treated as more directly identifying than a bare, opaque id (`visitors` holds no PII
at all; a Redis rate-limit bucket hashes an IP specifically because the cleartext value is itself
sensitive). `acceptance_records` carries no foreign key to `visitors`/`operators`/`sites` (`adr/0111`)
and is retained indefinitely as evidence of a lawful basis - which makes it exactly the kind of row
where "the data must exist somewhere" and "the data must be shown on an ordinary settings screen" can
be pulled apart, rather than assumed to be the same choice.

## Decision

`GetSiteConsentAcceptancesHandler`'s response DTO (`SiteConsentAcceptanceDto`) carries `SubjectKind`,
`SubjectId`, `DocumentVersion` and `AcceptedAt` only. `ClientIp`/`UserAgent` are not selected, not
mapped, and not serialized anywhere on this path - the omission is structural (the type has no such
properties), not a rendering choice made in the console.

The columns are untouched in Postgres and remain readable by anyone with direct database access (a
platform owner investigating an incident, an export built later) - this ADR narrows one read surface,
not the record itself. `IAcceptanceRepository.GetForDocumentKeyAsync` (the port this handler calls)
returns the full `AcceptanceRecord` aggregate; the DTO mapping in the handler is where the two fields
are dropped.

## Consequences

**Positive.** A tenant checking "who accepted, and when" - the question this screen exists to answer -
gets exactly that, with no incidental widening of what an ordinary admin screen exposes about a
visitor's own device or network. The subject shown is already a bare, opaque id (`visitors` holds no
name, no contact detail) - adding an IP address next to it would be the first place in this console
where a visitor becomes locatable from an admin screen with no extra step. This follows the same
minimisation posture `personal-data.md` already states for this system as a whole: "minimisation is
real but it works on retention, not on fields" - here it also works on *read surface*, a second axis
that document did not previously need to name.

**Negative, named rather than hidden.** A tenant who genuinely needs to defend a consent record to a
regulator or in a dispute - the scenario `24-01` built `ClientIp`/`UserAgent` for in the first place -
cannot get that evidence from this screen. Today they would need to ask an engineer to query the
database directly, which is a smaller version of the exact gap `adr/0114`'s own Context names for
document text: a mechanism that requires a terminal to reach. Unlike that gap, this one is not closed
by this item, and is named here so it is a decision to revisit rather than a fact nobody stated.

## Alternatives considered

- **Show `ClientIp`/`UserAgent` on the same table.** Rejected for now: nothing in `23-37`'s own
  Done-when asks for it ("which version did this person accept, and when" is the literal question),
  and showing it by default on every load would be the wider-than-asked-for exposure this ADR exists
  to avoid. Revisit if a real tenant asks for evidentiary detail this screen cannot give them.
- **A second, separate "evidence" view or export, gated more strictly than `site:configure`.**
  Considered and set aside as a follow-up rather than built speculatively (`clean-architecture.md`: an
  abstraction with one caller is a guess about the second one) - there is no second caller yet, and
  inventing a stricter gate for a screen nobody has asked for would be exactly the premature
  generalisation the platform's own qualifying rules warn against.
- **Mask instead of omit** (e.g. a truncated IP, the way `adr/0123` masks a contact value with a
  reveal). Rejected: masking exists to let a caller *reveal* a value they are otherwise trusted to see
  in full, the same permission gating both states (`adr/0123`'s own reasoning, "a rung governs what a
  list shows, never who may reveal"). Nothing about this screen's `Permission.SiteConfigure` gate
  changes between "showing a masked value" and "showing nothing" - there is no second, stronger
  permission a reveal could sit behind, so masking would only add UI complexity for a value this
  decision does not intend to surface here at all.
