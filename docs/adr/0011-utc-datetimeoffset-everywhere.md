# ADR-0011: All instants are UTC `DateTimeOffset`, rendered per request

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 1

## Context

A chat is a timeline. Visitors, operators and servers sit in different time zones, DST shifts twice a
year, and a message ordered by a client clock is a bug waiting to be reported as "messages appear in
the wrong order". Time-zone handling is also one of the fastest ways for a reviewer to judge whether
a codebase was written carefully.

## Decision

- **Storage**: every instant is UTC, in `timestamptz`. No naive local times anywhere, ever.
- **In code**: `DateTimeOffset`, never `DateTime`. Obtained from `IClock`, never from
  `DateTime.UtcNow` outside Infrastructure - enforced by an arch test.
- **On the wire**: ISO-8601 with an explicit offset (`2026-08-20T14:03:11.123+00:00`). Never a naive
  string, never a Unix timestamp without units.
- **Rendering**: the client sends its IANA zone (e.g. `Europe/Moscow`) on the handshake and in
  requests where it matters; the server renders user-facing text in that zone. With no zone supplied,
  render UTC and **label it as UTC** in the output - an unlabelled timestamp is a defect.
- **Ordering** never depends on any clock: within a conversation, order is the server-assigned
  `sequence` (`concurrency.md`). Timestamps are for display and analytics, not for sorting.
- Dates that are genuinely calendar days (retention windows, daily reports) use `DateOnly` plus an
  explicit zone, because "a day" is not a duration.

## Consequences

- Cross-zone displays, DST boundaries and clock skew stop being able to corrupt ordering.
- Analytics need an explicit zone parameter, which is friction - and the correct kind, since a daily
  report without a stated zone is meaningless anyway.
- Cost: `DateTimeOffset` in EF and Dapper mappings needs care per provider, and MySQL (Stage 9)
  handles offsets differently from `timestamptz`. That friction goes on the Stage 9 list.

## Alternatives considered

- **`DateTime` with a UTC convention** - one careless `DateTime.Now` and the convention is silently
  broken, with no type-level trace.
- **Storing local time plus a zone name** - required for future scheduled events, unnecessary here,
  and it makes every comparison a conversion.
- **NodaTime** - genuinely better modelling (`Instant`, `ZonedDateTime`). Rejected for now to keep
  the mapping story simple across two ORMs and two databases; revisit if scheduling arrives.
