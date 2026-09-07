# a tenant sees what their storage holds and can clear it

- **Stage**: 23
- **Status**: ready
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

- [ ] A tenant sees how much of their quota is used, and it agrees with what enforcement believes.
- [ ] They see every attachment across every conversation, sortable by size, type, age, conversation and
      sender.
- [ ] They can select many and delete them, seeing the space to be freed before confirming.
- [ ] A deleted attachment leaves a readable transcript rather than a hole.
- [ ] Never-downloaded and duplicate views exist, because they are the two that carry judgement.
- [ ] The read is tenant-scoped, proven by fault injection rather than by inspection.
