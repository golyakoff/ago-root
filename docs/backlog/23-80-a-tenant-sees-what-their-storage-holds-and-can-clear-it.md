# a tenant sees what their storage holds and can clear it

- **Stage**: 23
- **Status**: done — `ago-chat#288`, `ago-console#225`. Independently re-verified by the managing
  session before merging (its own `dotnet build`/`test` and `npm` runs against the worker's own
  worktrees — 3303/3303 and 1380/1380, both matching the worker's reported counts exactly). Two real
  gaps found during that review, neither fixed here since both are out of this item's own scope: a
  pre-existing defect in `5-08`'s own delete path (`25-79`), and a named, non-regressing residual in
  `ago-widget` (`25-80`).
- **Depends on**: `23-76` enforces the quota. This is what a tenant does when it fills.
- **Decision**: the author's, 2026-09-07 — quotas need a way to act on them, not only a number.

## Why a quota without this is a trap

`23-76` gives every tenant a storage ceiling. A ceiling with no way to see what is under it, and no way
to remove anything, is a wall a customer hits and cannot walk back from. They would have exactly two
options: pay more, or write to us. Both are worse than a screen.

So this is not a companion feature. **A quota that ships without it converts every heavy user into a
support ticket.**

## Where it lives

**Администрирование → Хранилище.** Not inside a conversation: the whole point is to see across every
conversation at once, which is the one view no existing screen offers.

## What it shows

- **How much of the quota is used**, plainly, at the top. A number and a bar. This is the thing the
  author asked for first and it is the reason most people will open the screen.
- **Every attachment the tenant holds**, in one table: name, size, type, which conversation, who sent it
  (visitor or operator), when, and whether it has ever been downloaded.

## Sorting and filtering, in order of how useful they actually are

- **By size, descending — the default.** One 5 MB file is worth forty small ones, and somebody clearing
  space wants the top of that list, not an alphabet.
- **By type.** Images and PDFs behave differently in a person's head; a shop clearing "screenshots from
  two years ago" is doing a different job from one clearing invoices.
- **By conversation and by who sent it.** A visitor's uploads and an operator's are different property
  in the tenant's mind, whatever they are in ours.
- **By age**, which is what most cleanups are actually keyed on.

Three more worth having, and they are the ones that make the screen more than a file browser:

- **Never downloaded.** An attachment nobody has ever opened is the safest thing to delete, and this is
  the only signal on the screen that carries any judgement about *value*.
- **Duplicates by content hash.** The same bytes uploaded repeatedly cost space and carry no extra
  information; deleting all but one is free space with zero loss. It also pairs with `23-76`'s
  deduplication, which would make this list mostly empty — worth building the view first and seeing.
- **Largest conversations, not only largest files.** A conversation with forty small attachments can
  outweigh one big file, and nothing else on the screen would surface it.

## Bulk deletion, and the part that is not about the button

- Select many, delete once, and **show what will be freed before the confirm** — a count and a total in
  megabytes. "Delete 43 files, 312 MB" is a decision; "Delete selected" is a guess.
- **A deleted attachment must leave an honest transcript.** The message stays and the attachment becomes
  a plain marker that a file was removed — not a broken link, not a missing image with a red cross.
  `adr/0108` already rewrites rather than deletes an archived object for exactly this class of reason;
  follow that instinct rather than inventing a second one.
- **This is housekeeping, not erasure.** A tenant clearing space is not a data-subject request and must
  not be recorded as one. `24-09`'s and `adr/0113`'s records answer a different question and should not
  fill up with a tenant tidying their own disk.

## Where this is likely to go wrong

- **Somebody will delete a customer's invoice.** A preview, and an obvious undo window, are worth more
  here than anywhere else on the console.
- **The screen is a list of everything a tenant holds**, which makes it the widest read of attachment
  metadata in the product. It is `site:configure`-shaped, not operator-shaped, and it must be
  tenant-scoped with a proof rather than a comment.
- **Counting is not free.** A tenant with a hundred thousand attachments needs the total to come from
  something maintained, not from summing rows on every page load.

## Done when

- [x] A tenant sees how much of their quota is used, and it agrees with what enforcement believes.
      `/account/storage`'s own quota bar reads `GetSiteAttachmentStorageSummaryHandler`, which reads
      `sites.attachment_bytes_reserved` - the exact column `23-76`'s own `ISiteAttachmentStorageBudget`
      already maintains, through a new bare-read port rather than a second computation. Proven against
      real Postgres: `StorageSummary_UsedBytes_AgreesWithTheBudgetEnforcementFigure`
      (`ago-chat/tests/Ago.Chat.Integration.Tests/SiteAttachmentStorageHandlersTests.cs`).
- [x] They see every attachment across every conversation, sortable by size, type, age, conversation and
      sender. All five sort orders and both judgement filters are real, keyset-paginated queries against
      real Postgres. **One honest gap**: there is no "name" column - `Attachment` (`ago-chat`) has never
      captured an uploaded file's original filename (`personal-data.md`'s own existing line: "Attachments
      never carry the visitor's filename"), and adding one would be a wire-shape change reaching the
      widget's own upload call, out of this change's repository scope (`ago-chat`/`ago-console` only).
      Content type stands in for it on the screen, named as a substitution rather than hidden.
- [x] They can select many and delete them, seeing the space to be freed before confirming. The
      dialog states the selected count and total bytes before the destructive action, sourced from the
      already-fetched rows client-side (no extra round trip). **Not built**: the "obvious undo window"
      the item's own "Where this is likely to go wrong" section names as worth more than anywhere else on
      the console - the delete is immediate and permanent, same as `5-08`'s own single-attachment delete
      already was. Flagged, not silently dropped.
- [x] A deleted attachment leaves a readable transcript rather than a hole. The message row itself is
      never touched by a delete (`Attachment.MarkDeleted` never rewrites `Message.AttachmentId`) - proven
      by sending a real message through the real pipeline, bulk-deleting its attachment, and reading the
      row back (`BulkDelete_LeavesTheMessagesAttachmentReferenceIntact_AndDownloadNowAnswersRemoved`).
      Resolving that reference now answers a new, distinct, permanent `Attachment.Removed` code rather
      than the pre-existing `Attachment.NotReady` (which also covers a merely-still-uploading attachment -
      a different, retryable case that must not read the same way). Reaches all the way to both consoles'
      own UI: `ago-console`'s `ConversationPage` renders the identical "Attachment deleted" marker for a
      removal it did not itself perform (another operator, or a tenant's own bulk-delete) as it already
      did for its own local delete action - proven by
      `ConversationPage.test.tsx`'s two new cases, with a fails-before run confirming the mutation is
      caught (see the session's own report). `ago-widget` was not touched - out of this change's
      repository scope; the visitor-facing widget still needs the identical fix, named here as a
      residual, not assumed done by association.
- [x] Never-downloaded and duplicate views exist, because they are the two that carry judgement. Both
      are real `WHERE` predicates against real Postgres, the duplicates one reusing `23-76`'s own
      `ix_attachments_site_content_hash` partial index via a per-row `EXISTS` rather than a whole-table
      window function (`SiteAttachmentListReadStore`'s own remarks on the cost tradeoff). Proven:
      `ListSiteAttachments_NeverDownloadedFilter_...`/`ListSiteAttachments_DuplicatesFilter_...`.
- [x] The read is tenant-scoped, proven by fault injection rather than by inspection. All five routes
      (`GET .../attachments`, `.../largest-conversations`, `.../storage-summary`, `.../egress`,
      `POST .../bulk-delete`) proven over real HTTP with a real Keycloak token and a real, privileged
      caller naming another tenant's `siteId` - `SiteAttachmentStorageRoutes_RefuseAnotherTenantsSite_AndDeleteNothing`
      in `CrossTenantRouteIsolationTests`, the same class and shape `tenant-isolation.md` already
      documents as this codebase's standard for exactly this claim, extended rather than duplicated. A
      fails-before run (the permission check disabled) confirmed the test actually catches the
      regression before this change restored it.
