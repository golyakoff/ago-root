# 26-21 · Prove the RuStore Push adapter against a real RuStore project

- **Stage**: 26
- **Status**: ready — blocked on a real RuStore Console project existing, not on design or code
- **Found**: 2026-09-22, carrying out `26-04`'s own remainder. `26-04` shipped everything provable
  without a live RuStore project (the port, the error-code classification with a test per outcome, the
  ttl decision, the metrics, the `secrets.md` row) and left four Done-when boxes genuinely unsettled
  for the identical reason: nobody has opened https://console.rustore.ru yet, so there is no project
  id and no service token to send a real message with. This is that remainder, given its own number
  per this project's own rule rather than left as an open box under a closed item.
- **Depends on**: a human creating a RuStore Console project (push notifications section) and issuing
  a service token — an account-provisioning step, not an engineering one. Nothing here can start
  before that exists.

## What this item is

`26-04`'s `RuStorePushSender` was written against RuStore's own published documentation, with two
named, honest guesses (the `message.data` payload shape, and the `android.ttl` wire format) and one
mechanism (revocation on a terminal error) that has never actually run against the real service. This
item is the four proofs that require it to exist.

## Scope

- **A real send, proven.** `RUSTORE_PUSH_SERVICE_TOKEN` and a real `projectId` configured (locally or
  against a real deployment — whichever this project's own state supports at the time), one message
  sent to a real, registered device token, and the outcome observed directly (not inferred).
- **Settle the `message.data.payload` ambiguity** (`adr/0180` §3, `RuStorePushSender.BuildData`'s own
  remarks): does RuStore's validator want a flat `data` map, or a nested `payload` key inside it? The
  real send answers this. Update `RuStorePushSender.BuildData` if the flat-map guess turns out wrong,
  and update `docs/architecture/push-notifications.md`'s own note on this with the real answer either
  way.
- **Prove revocation end-to-end, both directions.** A revoked or otherwise-dead device token sent a
  real push updates the `26-03` `operator_devices` row (`RevokeByTokenAsync`) — and a **deliberately
  wrong service token** does **not** revoke anything, proven by sending with one on purpose and
  confirming the device row is untouched. The second proof matters more: getting it backwards empties
  the whole table silently the first time the credential itself is ever wrong.
- **Answer whether a RuStore project can hold two live service tokens at once** (the rotation-class
  question `RuStoreOptions.ServiceToken`'s own remarks and `secrets.md`'s own row leave open) — found
  from the real console, not guessed. Update the rotation class in both `secrets.md` and
  `push-notifications.md` if the answer is `Draining` rather than the currently-recorded `Restart`.

## Out of scope

- Anything the real send does not touch — the port shape, the error-code table's classification logic
  for outcomes other than the two revocation cases above, and the metrics are already proven by
  `26-04`'s own unit/integration tests and are not re-litigated here.
- `26-05`'s fan-out consumers, `26-06`/`26-18`'s Android client half — this item only proves the
  adapter `26-04` already wrote, against the real service it was written for.

## Done when

- [ ] A real send to a real device token completes, and the outcome (delivered, or a real terminal/
      transient classification) is recorded here.
- [ ] The `message.data.payload` ambiguity is settled, with the real answer, and
      `push-notifications.md` updated to match — including a code change to `RuStorePushSender` if the
      flat-map guess was wrong.
- [ ] A revoked/dead token's send updates the `26-03` device row; a wrong service token's send does
      not touch it — both proven, not assumed.
- [ ] Whether a project can hold two live service tokens is answered from the real console;
      `secrets.md`'s and `push-notifications.md`'s rotation-class rows reflect the real answer.
- [ ] `dotnet format`/`build`/`test` all green if any code changed as a result of what this item finds.
