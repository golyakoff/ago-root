# Widget branding: does "styles/theme" extend beyond color and position?

- **Stage**: 11
- **Status**: blocked
- **Depends on**: `11-01-widget-config-data-model-and-api.md` if it proceeds (would extend the same
  `WidgetConfig` value object and migration rather than starting a new one)

## Goal

Stage 11's roadmap text lists three things: "colors, styles/theme, position on the host page."
`11-01`/`11-02`/`11-03` ship exactly two of the words in that list, on the reading that "styles/theme"
describes what the primary color drives (the visual theme *is* the color, in a small fixed-field
system), not a third, independent axis of configuration. That reading is defensible — Stage 11's own
done-when text tests only "changes color/position," nothing else — but it is a reading, not something
the roadmap or any architecture doc actually confirms. This item exists to hold the real question open
rather than let the narrower scope quietly become the permanent definition of "widget customization" by
default.

## Context to read first

`docs/roadmap.md`'s Stage 11 section, read literally, side by side with `11-01`'s ADR (once written) —
the gap between the roadmap's three-word list and the two fields actually shipped. `docs/backlog/11-01-widget-config-data-model-and-api.md`'s
own ADR — the reasoning that ruled out arbitrary CSS injection applies to *any* additional styling
surface this item might add, not just the two fields already shipped; whatever this item eventually
scopes, it inherits that same "named, validated fields, not free-form CSS" constraint. `docs/architecture/file-storage.md` —
if the answer below includes a logo/avatar image, that is a real attachment-shaped feature (presigned
upload, storage, a moderation/content-safety question distinct from a chat attachment because this
image renders on every page load of every visitor's browser across a tenant's site, not just inside one
conversation thread an operator already trusts) and needs the same rigor `5-02`/`5-03` already gave chat
attachments, not a shortcut. `docs/architecture/repositories.md`'s "no personal or employer data" and
general public-repo posture — mostly irrelevant here except as a reminder that any user-uploaded image
this project accepts is public-facing on someone else's site, a different trust boundary than an
internal chat attachment.

## The actual open question

Which of the following, if any, belong in "widget customization" beyond the primary color and launcher
position `11-01` through `11-03` already ship:

- A **custom logo or avatar image**, shown in the widget's header/launcher — the most likely candidate
  reviewers would expect from "make the embedded widget look like their own site" (the roadmap's own
  Goal sentence), but genuinely new scope: file upload, storage (reusing `5-02`'s `IFileStorage` port,
  presumably a new `site_id`-scoped object rather than a conversation attachment), a size/format
  ceiling, and a decision about whether this needs any moderation given it renders automatically on
  every visitor's page rather than being reviewed the way a chat message attachment implicitly is by an
  operator seeing it first.
- A **second color** (background, or a text color independent of the primary accent) — a small,
  low-risk extension of `11-01`'s existing fixed-field pattern if wanted, cheap to add later regardless
  of when it's decided.
- A **light/dark mode toggle**, independent of the primary color — a real design decision (does the
  widget compute contrast against an arbitrary primary color and pick text colors automatically, or does
  the tenant pick a whole named theme) that `11-01`'s two fields do not attempt to answer.
- **Nothing further** — the roadmap's "styles/theme" was loosely worded, and `11-01`'s color +
  position is the intended full scope of Stage 11.

Any answer keeps `11-01`'s own "no arbitrary CSS" constraint — a wider field set is still a wider set of
*named, validated* fields, never free-form styling injected into the shadow tree.

## Why this is blocked and not guessed

The backlog's own discipline (`docs/backlog/README.md`) is that an item with a real, unanswered question
does not get started — and this genuinely is unanswered: nothing in `vision.md`, `roadmap.md`, or any
ADR states whether logo/branding-image support is in or out of AGO Chat's scope, and the project's own
commercial intent (this is meant to go past portfolio-only, toward real paying tenants) is exactly the
kind of context that could tip this either way without more actually being knowable from the repository
alone. Scoping it out silently would under-deliver against the roadmap's own wording without saying so;
guessing it in would add a real, non-trivial feature (file upload, a new trust boundary) nobody asked
for. Neither is this planning session's call to make.

## Out of scope

- Nothing yet — this item has no scope until the question above is answered. Once it is, whatever gets
  decided either folds into a widened `11-01`/`11-02`/`11-03` (if small, e.g. a second color) or becomes
  its own new backlog item with its own number (if large, e.g. logo upload, which would need its own
  data-model/API/console/widget split the same way `11-01`-`11-03` did).

## Done when

- [ ] The author has answered the question above; this file is rewritten (or split, or closed as "no
      further scope") to reflect the answer, and its `Status` changes to `ready` or the work is folded
      into the appropriate other item.

## Open questions

**Blocking**: does "styles/theme" in Stage 11's roadmap text mean anything beyond the primary color and
launcher position already shipped in `11-01`-`11-03` — specifically, is a custom logo/avatar image in
scope for this stage, and if so, does it need any content-safety review given it renders unattended on
every visitor's page? Author's decision needed; no default is assumed here.
