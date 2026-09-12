# 25-60 · An online operator goes offline after 10-15 seconds

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing — **not a duplicate of `5-18`**, confirmed by reading that item: `5-18`'s
  own root cause (the operator hub's origin check rejecting the console's own origin) was fixed and
  verified live 2026-09-05. The error text this bug reports (`linkDisconnectedDetail`, "...(5-18)") is
  a **permanent, generic citation** telling an operator to check the browser console for the real
  refusal reason — it is not evidence this is the same, already-fixed incident recurring.
- **Found**: 2026-09-12, `feedback.md` — a real, live occurrence: "! Офлайн | Нет соединения с
  сервером оператора..." appearing 10-15 seconds after an operator shows Online.

## Scope

- Reproduce live, with the browser console open, and read the actual connection-refusal reason the
  hub reports (the same `linkDisconnectedDetail` text already instructs an affected operator to do) —
  this alone should identify the real cause rather than guessing.
- Fix whatever that reason turns out to be. Candidates worth checking early, not assumed: a token
  expiring/refreshing mid-connection, a heartbeat/keepalive interval mismatch, a reverse-proxy or
  load-balancer idle timeout shorter than the hub's own, a reconnect loop that never actually
  re-authenticates.

## Where this is likely to go wrong

- **Don't assume this is `5-18` again without checking** — that item's own fix is verified live and
  a different, real cause is more likely than a regression of an already-fixed bug. Read the actual
  console error before proposing a fix.

## Done when

- [ ] The real disconnect cause is identified from an actual captured error, not inferred.
- [ ] The fix lands wherever that cause actually lives, and an operator staying Online for several
      minutes on a real connection no longer drops to Offline on its own.
