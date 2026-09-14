# 25-79 · Deleting an attachment never releases its quota reservation

- **Stage**: 25
- **Status**: ready
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

- [ ] `DeleteAttachmentHandler` releases the site's budget reservation on every successful delete,
      proven by a fails-before test (the release call removed, the test shows the reservation
      unchanged after a delete; restored, the test shows it shrink by the attachment's own size).
- [ ] Whether the live deployment's already-leaked reservations need a one-time reconciliation is
      decided and stated, not left implicit.
