# a visitor can keep a copy of the conversation

- **Stage**: 23
- **Status**: ready — **and it carries one product question, named below**
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

## The question, and it is the author's

**What is in the file, and in what format?**

- **Plain text** is honest, tiny, opens anywhere, and loses the pictures. Recommended for a first
  version: a visitor who wants the address wants the words.
- **HTML** keeps the shape and the images, and it is a file that renders — including anything an
  attachment link points at, which may or may not still be reachable when they open it.
- **PDF** is what people expect from "save", and it is a new dependency in the widget, whose bundle
  budget is measured in kilobytes and checked on every build.

The second half of the same question: **do attachments come with it, or only their names?** Bundling
them means the file is no longer small; not bundling them means a saved conversation contains links
that may expire, which is worse than a name.

## Where this is likely to go wrong

- **The widget's bundle budget.** It is checked on every build against a hard number. A PDF library
  does not fit that conversation quietly.
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
- [ ] The format question above is answered in the change rather than settled by whatever was easiest.
- [ ] The widget's bundle budget still holds.
