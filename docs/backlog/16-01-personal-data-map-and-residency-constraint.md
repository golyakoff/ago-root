# The personal-data map, and residency as a standing constraint

- **Stage**: 16 — but **pulled ahead of its stage** (`roadmap.md`'s "Order" section): two open vendor
  questions that are live right now, `10-05`'s email provider and `15-02`'s backup destination, cannot
  be answered correctly without the constraint this item records
- **Status**: **done 2026-08-25** (`e5770a0`) — all five Done-when met. The line said `ready` for a
  day after the work had merged, and the queue row outlived it too: both were caught by a sweep on
  2026-08-26 that compared every queue row against its item's own Done-when list. That is the failure
  this project keeps repeating, and it is why the check is now mechanical rather than remembered.
- **Depends on**: nothing

## Goal

The project knows what personal data it holds and where, and the residency constraint that binds
several already-open vendor decisions is written down before those decisions are made rather than
after. `docs/architecture/personal-data.md` is the artifact; this item is the work of keeping it
true and wiring its constraints into the items they bind.

## Context to read first

`docs/architecture/personal-data.md` — written alongside this item; it is the starting inventory, not
a finished one. `docs/architecture/data-model.md` — the tables it maps, and one sentence this item
corrects: `visitors` is described as "Anonymous, no PII by design", which is accurate about that row's
columns and misleading about the dataset, since `messages.body` next to it is whatever a visitor
typed. `docs/backlog/10-05-transactional-email-delivery.md` and `15-02-backup-and-verified-restore.md`
— the two open vendor questions this constraint binds. `adr/0026` — the deployment is already in
Russia, for cost and latency reasons; this item is what turns that into a recorded constraint instead
of a happy accident.

## Scope

- Keep `personal-data.md` accurate as the system changes, and make that a real obligation rather than
  an aspiration: add the check to the places a session actually looks — a line in `db-migration`'s
  guidance for any migration adding a column that holds a person's data, and the same for a new
  integration-event field.
- Correct `data-model.md`'s "Anonymous, no PII by design" so it says what is true of the row without
  implying it is true of the conversation.
- Write the residency constraint into the two items it binds (`10-05`, `15-02`), so the vendor answer
  is chosen against it rather than measured against it afterwards.
- State the two properties that currently make erasure tractable — body-free integration events
  (`MessageAccepted`), body-free webhook payloads (`6-05`) — as properties to be preserved, in the
  files where someone would be tempted to break them (`messaging.md`, `api-design.md`).
- No new mechanism, no schema change, no code. This item is documentation and cross-referencing, and
  it is deliberately small so it can land ahead of its stage without dragging Stage 16 with it.

## Out of scope

- Building deletion (`16-02`) or export (`16-03`).
- Answering the vendor questions themselves — `10-05` and `15-02` still own their own decisions; this
  item only ensures they are made with the constraint visible.
- The legal determination of AGO's role, the published policy text, or regulator notification — those
  live in `ago-business` and need a lawyer.
- Auditing logs and traces for personal data — `16-05`, which needs real running instrumentation to
  look at rather than a reading of the docs.

## Done when

- [x] `personal-data.md` exists, lists every store, and is referenced from `data-model.md`.
- [x] `data-model.md`'s "no PII by design" sentence is corrected.
- [x] `10-05` and `15-02` each carry the residency constraint in their own Open questions, so neither
      can be answered without it.
- [x] `messaging.md` and `api-design.md` state that integration events and webhook payloads stay
      body-free, and why that is now a privacy property and not only a size one.
- [x] The migration guidance names the map as something a schema change updates
      (`db-migration` step 6, and the same obligation in `messaging-contract` step 1 for a contract
      field).

## What the verification pass found

The item was written as "recording what is already true", so the work that mattered was checking
whether it *was* true. Every row of the table now cites the entity, migration, manifest or config it
came from. Five things did not survive that check.

- **`visitors.token_hash` does not exist and never did.** Both `personal-data.md` and `data-model.md`
  described the column; `Stage1CreateChatSchema`, the EF model snapshot and `Visitor.cs` all say the
  table is `id`, `site_id`, `first_seen_at`, `last_seen_at`, and the string does not occur anywhere in
  `ago-chat`. The visitor token is a stateless signed JWT the server never stores. Both files
  corrected.
- **Message bodies do cross the broker.** The realtime fan-out serialises a full `MessageDto` into
  `NodeDelivery.PayloadJson`, published `Persistent = true` onto a durable queue. The claim that
  message content lives in exactly two places was true of Postgres and not of the system. Bounded, and
  recorded with its bound.
- **Nothing is ever deleted automatically, anywhere,** except Redis TTLs and the attachment orphan
  sweep. No message pruning, no outbox or inbox trim, no webhook-delivery trim, no queue purge, no
  retention policy this project owns for logs or traces. The map now says so under its own heading
  rather than leaving it implied by fourteen "Removal path" cells.
- **Attachments never carry the visitor's filename** — `CreateAttachmentRequest` is
  `(ContentType, SizeBytes)` and the extension comes from the server's allowlist. A real minimisation
  property that nothing had recorded; `file-storage.md`'s step 1 claimed the opposite and was
  corrected.
- **Redis is snapshotted to a PVC.** Both the manifest and `docker-compose` mount `/data` and pass no
  `command:`, so `redis:7-alpine`'s built-in save points apply. Expiry survives a reload so nothing
  comes back alive, but "it is only in memory" was not a safe assumption to carry into `15-02`.

## Found but deliberately not built

Both are mechanisms, and this item is a document.

- **Deleting a conversation orphans its MinIO objects.** `attachments` rows cascade from
  `conversations`; the bytes do not, and the orphan sweeper only claims rows that never got a
  `message_id`. `16-02` already lists MinIO in its reach — this is the specific shape of the trap it
  has to avoid, not a new item.
- **Leaked node queues can hold message text indefinitely.** The node id is the pod name, the queue is
  `durable, autoDelete: false`, and each pod replacement leaves one behind; the matching `*.dlq` has no
  TTL and no consumer either. `NodeDeliveryConsumer`'s own remarks already accept the queue leak — what
  nobody had written down is what the leaked queue contains. **This needs an owner and has none**;
  `15-04` (retention and pruning jobs) is the closest fit, since it is the item that would be adding
  the project's first retention mechanism anyway.

## Open questions

None of this item's own. Five facts it could not establish from the workspace are listed in
`personal-data.md`'s *What is unestablished* section rather than guessed — chiefly what Keycloak's
brute-force protection and session store actually persist now that `adr/0036` gave it a real database,
which `15-02` should settle before it decides what a backup contains. `16-05` owns the logs-and-traces
half.

**No ADR was written.** `0039` was reserved for this item and is left unclaimed: nothing here chooses
between real alternatives. The residency constraint is a consequence of `adr/0026` plus a statute, not
a decision this item made, and the decisions it binds (`10-05`'s provider, `15-02`'s destination) are
the ones that should carry ADRs — made against the constraint rather than justified afterwards, which
was the whole reason for pulling this item ahead of its stage.
