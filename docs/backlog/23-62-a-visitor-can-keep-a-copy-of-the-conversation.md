# a visitor can keep a copy of the conversation

- **Stage**: 23
- **Status**: ready — **the format question answered by the author, 2026-09-09, recorded below**
- **Depends on**: `23-61` reserves the place this control sits in.
- **Decision**: the author's, 2026-09-07 — a down-arrow icon in the compose area, «Сохранить диалог».

## Goal

A visitor can take away what was said — a quote, an address, a set of instructions — without
screenshotting it or trusting that the widget will still hold it tomorrow.

## Why this is a separate item from `23-61`

`23-61` is a layout. This is a feature that produces a file on somebody's computer, and the two make
different promises: one lands green when the composer looks right, the other when the file is correct.
`23-61` leaves the place; this fills it.

## What it is, and what it deliberately is not

**It is a copy of what the visitor can already see.** Not an export of everything we hold about them —
that is a data-subject request and a different mechanism with different rules. Nothing appears in the
file that is not on their screen: no operator notes, no internal events, no other conversation.

That distinction is worth stating plainly in the item because the two get conflated, and conflating them
turns a convenience into a compliance surface.

## The question, answered by the author, 2026-09-09

**What is in the file, and in what format?**

**A `.zip`, containing an HTML transcript.** HTML over plain text: it keeps the shape and the
pictures, and it renders anywhere without a new binary format in play. `.zip` rather than a bare
`.html` because of the second half of the same question:

**Do attachments come with it, or only their names?** **They come with it** — the actual attachment
files are pulled and bundled inside the archive alongside the HTML, not left as links. This is the
deliberate answer to the risk this item itself named: a saved conversation whose attachment links
have expired by the time it is opened is a worse copy than a larger file.

## Where this is likely to go wrong

- **The widget's bundle budget.** Checked on every build against a hard number. A PDF library was the
  risk this item first named; that is avoided by choosing HTML over PDF, but bundling real attachment
  bytes into a `.zip` client-side still needs *something* to build the archive (a small zip library,
  or the browser's own `CompressionStream`, is not the same footprint as a PDF renderer, but it is not
  zero either) — check it against the budget before assuming HTML alone settled this.
- **What "the conversation" means when history is paged.** The visitor sees what has loaded. A file
  that silently contains only the last page is a bad copy; a file that fetches everything is a new
  request path with its own scoping.
- **The file names a shop and a time.** It lands in a Downloads folder on a device somebody else may
  use. Nothing to solve here, but the file name should not be more revealing than it needs to be.

## Out of scope

- A data-subject export. Different mechanism, different rules, and it belongs with `24-09`'s
  neighbours.
- The operator's own copy. Operators have the console.

## Done when

- [ ] A visitor can save the conversation from the compose area and gets a file.
- [ ] The file contains what they could see and nothing else, asserted by a test.
- [ ] The saved file is a `.zip` containing an HTML transcript with the real attachment files bundled
      inside, per the author's decision above.
- [ ] The widget's bundle budget still holds.
