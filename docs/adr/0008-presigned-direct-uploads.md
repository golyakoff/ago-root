# ADR-0008: Presigned direct-to-storage uploads

- **Status**: Accepted
- **Date**: 2026-08-20
- **Stage**: 5

## Context

Chat needs attachments. The Api process simultaneously holds tens of thousands of long-lived
WebSockets, where memory per connection and predictable latency are the whole game.

## Decision

File bytes never traverse the Api process. The Api validates quotas and limits, records a `pending`
attachment, and returns a short-lived presigned PUT scoped to one key, method and content type. The
client uploads directly to S3/MinIO; the Api then verifies the stored object (existence, size, type)
before marking it `ready`. Downloads use short-lived presigned GETs after an authorisation check. A
sweeper deletes orphaned `pending` objects.

## Consequences

- The Api's memory and latency profile stops depending on user upload behaviour.
- Storage is swappable (MinIO locally, any S3 in the demo) behind `IFileStorage`.
- Cost: a multi-step protocol the client must implement correctly, and a verification step that is
  easy to skip. Both are written into `file-storage.md` so no session "simplifies" them away.
- Cost: orphan cleanup is now our problem; without it every abandoned upload leaks forever.

## Alternatives considered

- **Stream uploads through the API** - simplest client, and it puts multi-megabyte buffers and
  long-running requests inside the process holding all the sockets.
- **A separate upload service** - solves isolation, adds a deployable for something presigned URLs
  already solve.
- **Trusting the client's "uploaded" call** - saves one HEAD request and lets a client register
  attachments that do not exist.
