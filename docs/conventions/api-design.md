# API and protocol design

## HTTP

- REST-ish, resource-shaped, versioned by path: `/api/v1/...`. The widget is embedded on sites we do
  not control and cannot be forced to upgrade, so v1 is a promise.
- Plural resources, no verbs in paths. Actions that are not CRUD become sub-resources:
  `POST /api/v1/conversations/{id}/close`.
- `POST` returns `201` with a `Location`; idempotent retries of a create carry a client-supplied
  idempotency key and return the original result rather than a second row.
- Errors are RFC 7807 problem details with a stable machine-readable `type` and a `traceId`. Error
  text is for humans; clients branch on `type`, never on the message.
- Pagination is keyset only: `?before=<cursor>&limit=<n>`, response carries the next cursor. No page
  numbers, no `OFFSET` (`data-model.md`).
- Timestamps are ISO-8601 with offset (`date-and-time.md`).

## Realtime protocol

- Hub methods are thin transports; payload shapes live in `Ago.Chat.Contracts` and are versioned with
  the same additive-only rule as integration events.
- Client -> server messages carry `clientMessageId` for deduplication; server -> client messages carry
  the persisted id and `sequence`.
- Anything a client can send at high frequency (typing, presence) is throttled client-side and
  coalesced server-side, and never persisted.
- The client resumes by sending its last known `sequence` per conversation; the server replies with
  the delta. Reconnect must be cheap, because reconnects are normal (`adr/0010`).

## Widget-facing constraints

- CORS is per-site, driven by `allowed_origins` from the database, never by a wildcard and never by
  an ingress annotation (`edge.md`).
- The public site key identifies a tenant; it is not a secret and grants nothing beyond starting a
  visitor session. Anything sensitive requires the signed visitor token.
- Everything the widget calls is rate-limited per site and per visitor (`caching.md`), and returns
  `429` with `Retry-After`, which the widget must honour with jittered backoff.
- Payload ceilings are small and enforced; file bytes never come through the API (`adr/0008`).

## Compatibility

Additive changes only within a version: new optional fields are fine, renamed or removed fields are
not. Breaking changes ship as `/api/v2` alongside v1 until the widget population has moved - and
since we cannot force a shop to update its script tag, "until" is measured in months, not days.
