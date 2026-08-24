# Erasure: deleting an account, and deleting a conversation on request

- **Stage**: 16
- **Status**: ready
- **Depends on**: `16-01-personal-data-map-and-residency-constraint.md` (the map is what makes a
  deletion complete rather than plausible), `15-01-keycloak-persistent-user-store.md` (deleting a
  Keycloak user is meaningless while the user store is ephemeral), and `15-02-backup-and-verified-
  restore.md` for its retention window — the two items must agree on one number, see Scope

## Goal

A tenant can delete their account and everything in it, and can delete one visitor's conversation on
that visitor's request, with both removals reaching every store the data actually sits in rather than
only the obvious table. Today neither exists: a repository-wide search finds no account deletion, no
conversation deletion, and no erasure path of any kind.

## Context to read first

`docs/architecture/personal-data.md`'s "Where it lives" table — the checklist a deletion has to
satisfy, and the two stores (`outbox`, `webhook_deliveries`) that deliberately hold no copies, which
is what keeps this item finite. `docs/architecture/file-storage.md` and `docs/backlog/5-04-attachment-
thumbnails-and-orphan-sweep.md` — attachments and thumbnails are two objects per attachment, and the
sweeper is an existing mechanism to reuse rather than a second one to write. `docs/architecture/data-
model.md`'s partitioning section — `messages` is partitioned, so a per-conversation delete and a
whole-partition drop are different operations with different costs. `docs/architecture/caching.md` —
cached site config and any cached read model must be invalidated, not left to expire, when the thing
they describe is gone. `docs/backlog/15-04-retention-and-pruning-jobs.md` — the bounded-batch deletion
shape already established there, to be reused here rather than reinvented.

## Scope

- **Tenant account deletion**, initiated from the console by someone holding the right permission
  (`adr/0016`'s RBAC — decide whether this needs a new permission or the existing `site:configure` is
  too broad for it; a single boolean that destroys a business is a plausible case for its own).
  Reaches: conversations and messages, attachments and thumbnails in MinIO, the site row and its
  config, operators and role assignments, the Keycloak users belonging to it, and any cached entry
  derived from them.
- **Conversation deletion on a visitor's request**, initiated by the tenant (the visitor has no
  account and no login — they ask the shop, the shop acts). Same reach, narrower scope.
- **Deletion is a job, not a request handler.** These touch many rows across several stores and can
  fail halfway; they belong in `Ago.Chat.Worker` in the same shape as `15-04`'s prune and the existing
  `OutboxDispatcher`, with a recorded, resumable state, not in a synchronous HTTP call that a
  timeout can tear in half.
- **The archive, added by `adr/0031` (2026-08-25)**: expired history is archived to object storage
  rather than deleted, so erasure has one more store to reach and a deletion is not complete while an
  archive object still holds the data. This also constrains that store's class — a cold tier that is
  immutable or carries a minimum billable retention would make this item undeliverable, which
  `adr/0031` records as a selection constraint rather than a preference.
- **The backup answer, stated in one place**: deletion is complete when the last backup containing the
  data has aged out, and the window is `15-02`'s retention number. This item does not build a deletion
  journal replayed after restore — rejected deliberately, since such a journal is itself a list of
  people who asked to be forgotten (`personal-data.md`'s own reasoning). The two items must not carry
  two different numbers; whichever lands second adopts the other's.
- **Proof it actually removed everything**: an integration test that creates a tenant with
  conversations, messages, attachments and thumbnails, deletes it, and then asserts against every
  store in `personal-data.md`'s table — including MinIO objects and the Keycloak user — that nothing
  is left. A deletion test that only checks the rows it remembers to check is how erasure quietly
  becomes partial.
- Whatever the tenant sees while it happens: deletion is asynchronous, so the console must not claim
  it is done before it is.

## Out of scope

- Export — `16-03`. Offering "download your data before deleting it" is a sensible product pairing and
  a separate item; this one does not block on it.
- Retention-driven automatic deletion — `15-04`'s mechanism and `13-05`'s tier policy. Different
  trigger, same primitives; this item should use the same bounded-batch machinery and not duplicate it.
- Deleting a single message. Nothing asks for it, and the partial-conversation semantics (what an
  operator sees where a message used to be) is a product question nobody has raised.
- Anonymisation as an alternative to deletion — a real technique, and a real decision about whether
  free text can ever be considered anonymised. Not needed to ship this, and it would need its own
  argument.
- Regulator-facing records of deletion requests — `ago-business`, and a lawyer's question.

## Done when

- [ ] A tenant can delete their account from the console, and every store in `personal-data.md`'s
      table is emptied of their data.
- [ ] A tenant can delete one conversation, with the same completeness.
- [ ] Both run as resumable Worker jobs, in the existing job shape, not in a request handler.
- [ ] An integration test asserts emptiness across Postgres, MinIO and Keycloak after a deletion.
- [ ] Caches are invalidated rather than left to expire.
- [ ] The backup window is stated once and matches `15-02`.
- [ ] The console does not report completion before the job has completed.

## Open questions

None. The permission question is this item's to decide and state.
