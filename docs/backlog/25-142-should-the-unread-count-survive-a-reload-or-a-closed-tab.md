# 25-142 · Should the unread count survive a reload or a closed tab?

- **Stage**: 25
- **Status**: needs a decision - filed as the question, not yet scoped for implementation
- **Found**: 2026-09-18, while scoping `25-141` (the closed-launcher unread badge). Filed at the
  point CLAUDE.md's own rule names: an honest version of this item would decide something the author
  should decide, not something this session should assume either way.
- **Depends on**: `25-141` (this is that item's own in-memory-only limitation, made a decision rather
  than an unstated gap).

## The question

`25-141`'s badge lives in a plain in-memory counter - it is correct for exactly as long as the page
stays loaded. A visitor who closes the browser tab (not just the panel) and reopens the site later, or
simply reloads the page, sees no badge at all on the next load, even if operator messages arrived in
the meantime - because nothing about that count was ever written down anywhere.

The author's own original framing when this feature was first requested (2026-09-17) named exactly
this case: "как у нас на лендинге" (matching the landing page's own mockup), and the earlier analysis
of this request (before it was interrupted) flagged the same open question this item now files
formally: does "unread" mean "unread since the panel last closed in this page load," or does it mean
"unread since the visitor last actually looked," which can span page loads and even browser restarts?

## What would be needed for either answer

- **Simplest, in-tab-only (what `25-141` already builds):** no further work. A reload always shows
  zero unread, regardless of what arrived while the tab was gone.
- **Persisted across a reload, same tab:** `WidgetStorage` already tracks `lastKnownSequence` per
  conversation (`storage.ts:416,426`) as a reconciliation cursor. On a fresh page load, before the
  panel is opened, the count of "unread" messages could be derived by asking the server for messages
  newer than the stored cursor and counting the non-visitor ones - this needs a lightweight read this
  wire contract may not yet expose (a count, or a small page of messages since a sequence, without
  opening a live hub connection first) - check what `connect()`'s own history-replay path already
  fetches before assuming new plumbing is needed.
- **Persisted across a closed-and-reopened tab, or a different device:** the same mechanism as above
  covers "closed tab, same browser" for free (the cursor lives in `localStorage`, which survives a
  closed tab) - it does **not** cover a different device or a cleared browser profile, which would
  need a server-side "last read" concept per visitor identity, a materially larger change touching
  `ago-chat`.

## Where this is likely to go wrong

- Don't build the persisted version without checking whether `connect()`'s own bootstrap already
  fetches enough to compute this for free (it replays history on connect - see `ui/widget.ts`'s own
  `connect()` and its history-loop remarks) - a second, redundant fetch just to count unread messages
  before the panel is even opened would be exactly the kind of premature plumbing this project's own
  conventions warn against building without checking first.
- This is a product decision (how "unread" should read to a returning visitor) as much as an
  engineering one - don't let the technical path (what's cheap to build) silently decide the user-
  facing definition.

## Done when

Not yet defined - this item's own first deliverable is the author's answer to the question above,
which then determines whether this item is implemented, split further, or closed as "the in-tab-only
version in `25-141` is enough."
