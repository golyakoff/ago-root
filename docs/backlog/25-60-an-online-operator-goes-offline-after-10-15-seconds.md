# 25-60 · An online operator goes offline after 10-15 seconds

- **Stage**: 25
- **Status**: done — `ago-console#196`
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

- [x] The real disconnect cause is identified from an actual captured error, not inferred. Not a
      network or server-side cause at all: `ago-console`'s `OperatorConnectionProvider` gates its one
      `connection.start()` call on `usePermissions().tenancies` being non-null, but the effect that
      call sits in has `tenancies` in its dependency array with no guard against running a *second*
      time. `tenancies` does change reference a second time - `PermissionsProvider`'s own effect
      depends only on `accessToken` and calls `setTenancies(tenanciesResponse.tenancies)` with a
      brand-new array on every run, including every silent access-token renewal
      (`userManager.ts`: "renewal happens... roughly a minute before each access token expires" -
      sooner still for a token already close to expiry when the tab was opened or resumed). That
      second effect run called `connection.start()` again on a connection `@microsoft/signalr`
      already reports `Connected` - which the library rejects synchronously, with no network
      round-trip at all: `Error("Cannot start a HubConnection that is not in the 'Disconnected'
      state.")`. The provider's own `.catch` (from `5-18`) logged that error and set the badge to
      "disconnected" - the exact generic "Офлайн" / `linkDisconnectedDetail` text reported live -
      over a connection that had never actually dropped. Verified against the real
      `@microsoft/signalr@10.0.11` source (`HubConnection._startWithStateTransitions`), not assumed.
- [x] The fix lands wherever that cause actually lives, and an operator staying Online for several
      minutes on a real connection no longer drops to Offline on its own. Client-side only, in
      `ago-console` - `OperatorConnectionProvider.tsx` now tracks a `hasStartedRef` and skips the
      effect's body entirely once `start()` has been called once, so a later `tenancies` reference
      change (any subsequent token renewal) no longer re-invokes `start()` on an already-connected
      hub. No `ago-chat` change: the operator hub, its origin check (`5-18`, verified unrelated), the
      connection registry/heartbeat, and every timeout checked (Keycloak's `accessTokenLifespan: 300`,
      SignalR's own keep-alive/client-timeout defaults, the Gateway's proxy timeouts) were all read and
      ruled out - none of them was the mechanism, and the full `ago-chat` suite (2934 tests) was run
      unmodified to confirm nothing there needed to change. Regression test:
      `ago-console/src/realtime/operatorConnection.test.tsx` - "does not call start() again when
      tenancies resolves to a new array reference on a later render" - fails against the pre-fix code
      (reproducing the exact `Error("Cannot start a HubConnection...")` and the resulting
      `"disconnected"` badge) and passes after it. landed as `ago-console#196`, branch was
      `fix/25-60-operator-goes-offline-after-10-15-seconds`.
