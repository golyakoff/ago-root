# Dates and time

The rules. The reasoning is in `adr/0011-utc-datetimeoffset-everywhere.md`.

## Non-negotiable

1. **Store UTC.** `timestamptz` in PostgreSQL. Nothing naive, nothing local, ever.
2. **`DateTimeOffset` in code, never `DateTime`.** `DateTime` is banned outside generated code; the
   arch test enforces it. `DateOnly`/`TimeOnly` for genuine calendar values.
3. **Time comes from `IClock`.** `DateTime.UtcNow`, `DateTimeOffset.UtcNow` and `Guid.NewGuid()`
   appear only inside Infrastructure implementations. A rule you cannot control in a test is a rule
   you cannot test - and time-dependent behaviour is exactly what needs testing.
4. **Wire format is ISO-8601 with an explicit offset**: `2026-08-20T14:03:11.123+00:00`. No naive
   strings. No bare epoch numbers. Serialisation settings are configured once, at the host.
5. **Render in the user's zone when we know it, UTC labelled as UTC when we do not.** The client
   sends its IANA zone (`Europe/Moscow`, not a `+03:00` offset - offsets do not survive DST) on the
   handshake. An unlabelled timestamp shown to a human is a defect.
6. **Never sort by time.** Within a conversation, order is the server-assigned `sequence`. Clocks
   skew, NTP steps, DST repeats an hour; sequence does none of that.
7. **Durations are `TimeSpan`, and never computed by subtracting two timestamps from different
   clocks.** For elapsed time inside a process use `Stopwatch`/`TimeProvider`, not wall time.

## Practical notes

- Comparisons and ranges always happen in UTC. Convert at the edge (input parsing, output
  rendering), never in the middle.
- A "day" is zone-dependent: any daily aggregation takes an explicit zone parameter, and the report
  states which zone it used.
- Rounding is towards the past for "ago" style displays; never show a future timestamp for a stored
  event because of clock skew - clamp it.
- Test fixtures use a controllable fake clock, and at least one test runs across a DST boundary in a
  non-UTC zone. If that test never existed, the code has not been proven.
