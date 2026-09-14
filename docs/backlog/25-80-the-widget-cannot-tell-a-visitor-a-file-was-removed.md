# 25-80 · The widget cannot tell a visitor a file was removed

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, while landing `23-80`, which gave a deleted attachment a distinct,
  permanent `Attachment.Removed` (HTTP 410) instead of folding it into the retryable
  `Attachment.NotReady` (400) — `ago-console`'s `ConversationPage` was taught to render "Attachment
  deleted" for the new code in the same change. `ago-widget` was not touched (a different repository,
  out of that item's scope) and was checked, not assumed: `ui/widget.ts`'s `renderAttachmentInto`
  catches any failed `getAttachmentDownload` call generically and shows `attachmentUnavailable` for
  all of them alike.

## What is actually true — and what is not

**This is not a regression.** Before `23-80`, a deleted attachment's download request answered
`Attachment.NotReady`, and the widget's generic catch-all showed the same `attachmentUnavailable`
text it shows for any failure. After `23-80`, the same request answers `Attachment.Removed`, and the
identical catch-all shows the identical text. A visitor sees no behavioral change either way.

What changed is that `ago-console` can now say something more specific — "this file was removed" —
for the one case that is actually permanent, the same distinction `23-80`'s own Scope named for the
operator side. The widget has no equivalent, and a visitor who asks an operator "why can't I open
that file" gets an answer the operator's own screen already knows and the visitor's own screen
cannot show.

## Scope

- `ago-widget`'s `renderAttachmentInto` (and the download-info branch near it, `ui/widget.ts:1825`)
  distinguishes `Attachment.Removed` from other download failures the same way `ago-console`'s
  `attachmentsApi.ts`/`ConversationPage.tsx` now do, and shows a distinct, translated string instead
  of the generic `attachmentUnavailable`.
- Every other failure (network error, a genuinely transient `NotReady`, the API unreachable) keeps
  today's generic behavior — this item narrows one case, not the whole catch-all.

## Done when

- [ ] A visitor whose conversation references a since-deleted attachment sees a distinct "this file
      was removed" message, not the generic unavailable one — proven by a test, fails-before checked
      against today's catch-all.
- [ ] Every other download failure still renders the existing generic message, unchanged.
