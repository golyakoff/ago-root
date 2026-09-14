# 25-94 · The saved-conversation archive cannot say a file was removed either

- **Stage**: 25
- **Status**: ready
- **Depends on**: nothing
- **Found**: 2026-09-14, building `25-80` — the widget's live rendering path (`renderAttachmentInto`)
  now distinguishes a permanently-removed attachment (`Attachment.Removed`, HTTP 410) from every other
  download failure, but the widget's *other* attachment-reading path does not, and was deliberately
  left untouched by that item as out of its own Scope.

## What is actually true

`ChatWidget.fetchAttachmentLocationForExport` (`ui/widget.ts`) calls the identical
`getAttachmentDownload` `25-80` fixed, but discards everything about a failure into a bare `null`:

```ts
} catch (error) {
  logWidgetError(error);
  return null;
}
```

`archive.ts`'s own `fetchAttachmentLocation` contract (its own doc comment) already states this
plainly: `null` "if the lookup itself failed - an expired URL, a network error, or the attachment no
longer exists." All three collapse into the same case. Downstream, a `null` location renders the
identical generic sentence for every one of them:
`` `<div class="attachment attachment--unavailable">${escapeHtml(copy.attachmentUnavailable)}</div>` ``
— `copy.attachmentUnavailable`, from `modules/saveConversation/copy.ts`'s own small, separate string
table (not `ago-widget`'s main `i18n/en.ts`/`ru.ts` `25-80` added `attachmentRemoved` to).

This is the identical shape `25-80` closed for the live widget, one layer over: a visitor who saves
their conversation as a file sees "Attachment unavailable" for a message whose file was genuinely,
permanently deleted, the same as for one that merely hiccupped on the network — exactly what `25-80`'s
own item text called "not a regression, but a real gap" for the live case.

## Why `25-80` did not fix this too

`fetchAttachmentLocationForExport` is passed into `archive.ts` as a plain function value
(`AttachmentLocation | null`), and `archive.ts`'s own module boundary (`modules/saveConversation/`)
is deliberately not allowed to import back into `ui/widget.ts`/`attachments.ts` — the same isolation
that lets it be unit-tested without the whole widget. Widening `AttachmentLocation` to also carry an
error code, and teaching `archive.ts`'s own rendering to branch on it, is a second, separate promise
`25-80`'s own Scope never asked for and would have doubled that item's blast radius for a narrower,
lower-traffic path (an explicit user action - saving a transcript - rather than the ordinary
in-conversation render).

## Scope

- `fetchAttachmentLocationForExport` (or `AttachmentLocation` itself) carries enough of the failure
  to let `archive.ts` distinguish "this file was removed" from "the lookup failed for some other
  reason" - the identical distinction `25-80` already drew for the live path, without importing back
  into `ui/widget.ts`/`attachments.ts` (that boundary stays; the information crosses it, the import
  does not).
- `modules/saveConversation/copy.ts` gains its own `attachmentRemoved`-shaped string (it keeps a
  separate table from the main widget's `i18n/`, on purpose - match that existing shape rather than
  reaching into the main table).
- Every other export-time failure (network error, an expired presigned URL by the time the archive is
  built, the API unreachable) keeps today's generic `attachmentUnavailable` text in the archive,
  unchanged - this item narrows one case, the same discipline `25-80` used.

## Done when

- [ ] A saved-conversation archive built for a conversation referencing a since-deleted attachment
      shows a distinct "this file was removed" line in the transcript, not the generic unavailable
      one - proven by a test, fails-before checked against today's collapsed-to-`null` behavior.
- [ ] Every other export-time attachment failure still renders the existing generic message in the
      archive, unchanged - proven by a test, not only by inspection.
