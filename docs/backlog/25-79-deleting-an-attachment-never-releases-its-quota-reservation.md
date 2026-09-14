# 25-79 · Deleting an attachment never releases its quota reservation

- **Stage**: 25
- **Status**: done — `ago-chat#292`. Independently re-verified by the managing session before
  merging (its own `dotnet build`/`test` run against the worker's own worktree — 3334/3334 tests,
  matching the worker's own per-project counts exactly). Both Done-when boxes genuinely closed,
  including the reconciliation-tool decision — built and tested locally, deliberately not run
  against the live deployment, which is the author's own step whenever they choose to take it.
- **Depends on**: nothing
- **Found**: 2026-09-14, while landing `23-80`/`23-82` — `BulkDeleteSiteAttachmentsHandler`'s own
  Done-when needed "the space freed" to be true (`23-80`'s own "show what will be freed before the
  confirm"), which meant reading how `ISiteAttachmentStorageBudget.ReleaseAsync` is actually called
  today. It is not, anywhere `5-08` shipped.

## What is actually true

`Ago.Chat.Application.UseCases.DeleteAttachment.DeleteAttachmentHandler.HandleAsOperatorAsync`
(`5-08`) marks the attachment `Deleted` and removes the storage object, but never calls
`ISiteAttachmentStorageBudget.ReleaseAsync`. Every attachment ever deleted through that route —
the console's per-message delete action, live since `5-08` shipped — is still counted against the
tenant's quota (`sites.attachment_bytes_reserved`, `23-76`) today.

This is a one-directional leak: a tenant's reserved-bytes figure can only grow, never shrink, from
this path. A shop that regularly deletes attachments will eventually hit `23-76`'s ceiling while
their real storage use is well under it, with no way to see why (until `23-80`'s own storage screen
ships and shows the same number `23-76` enforces — at which point the two will visibly disagree,
which is how this would otherwise have been found in production rather than in a background worker's
report first).

`23-80`'s own new `BulkDeleteSiteAttachmentsHandler` does not repeat this gap — it releases the
reservation for every attachment it deletes — but that is a second, parallel delete path built
alongside the leak, not a fix to it.

## Scope

- `DeleteAttachmentHandler.HandleAsOperatorAsync` calls `ISiteAttachmentStorageBudget.ReleaseAsync`
  for the attachment's own `SizeBytes`, in the same transaction as `attachment.MarkDeleted()` —
  the identical shape `BulkDeleteSiteAttachmentsHandler` already established.
- **A real tenant's already-leaked reservation does not self-correct** — releasing bytes going
  forward does not un-leak bytes already double-counted from attachments deleted before this fix.
  Whether a one-time reconciliation (recompute `attachment_bytes_reserved` from the actual sum of
  `Ready` attachments, the same number `23-80`'s own storage-summary read already computes) is worth
  running against the live deployment is a real question this item should answer, not silently skip —
  name it even if the answer is "not yet, no real tenant has hit this."

## Done when

- [x] `DeleteAttachmentHandler` releases the site's budget reservation on every successful delete,
      proven by a fails-before test (the release call removed, the test shows the reservation
      unchanged after a delete; restored, the test shows it shrink by the attachment's own size).
      `DeleteAttachmentHandlerTests.HandleAsOperatorAsync_WhenTheOperatorHoldsThePermission_ReleasesTheSiteBudgetReservationForTheAttachmentsOwnSize`
      and its stricter sibling (`...ReleasesOnlyThisAttachmentsOwnSize`, seeded with other bytes
      already reserved so "shrinks to zero" cannot pass by accident) both fail red against the
      pre-fix shape and pass green against the fix — proven by actually reverting the release call,
      running the tests, and restoring, not asserted. Idempotency proven separately:
      `...WhenAlreadyDeleted_IsIdempotent_AndDoesNotReleaseTheBudgetASecondTime` shows a retried
      delete against an already-`Deleted` attachment releases nothing a second time (the fix's own
      one way to introduce a new bug while fixing the old one).
- [x] Whether the live deployment's already-leaked reservations need a one-time reconciliation is
      decided and stated, not left implicit. **Decision: build the report, do not run it.** A
      report-only script (`ago-chat/tools/attachment-quota-reconciliation-report.sh`,
      `ago-chat/docs/runbooks/attachment-quota-reconciliation.md`) recomputes each site's actual
      `Ready`-attachment byte sum and reports where `sites.attachment_bytes_reserved` disagrees with
      it — the same "reports, never repairs" posture `ago-deploy/k8s/tenancy-reconciliation-report.sh`
      already established for exactly this class of problem (a cross-referencing script that would be
      catastrophic the first time its own join is wrong). Built and verified against a local,
      disposable Postgres container only (seeded drift correctly detected and reported; a connection
      failure found and fixed to fail loudly rather than being silently read as "no drift" by an
      earlier draft) — **not run against the live deployment**, per this codebase's established
      posture that a tool touching real tenant billing/quota state is the author's own act, following
      the runbook, never a worker's or a managing session's without the author present. Whether any
      real, already-onboarded tenant has actually accumulated drift is therefore still genuinely
      unknown — the tool to find out exists and is ready, but nobody has run it for real yet.
