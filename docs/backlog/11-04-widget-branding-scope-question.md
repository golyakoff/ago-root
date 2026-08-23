# Widget branding: does "styles/theme" extend beyond color and position?

- **Stage**: 11
- **Status**: done (resolved as no further scope)
- **Depends on**: nothing — closed out, not built

## Resolution (2026-08-23, author's decision)

**No logo/avatar image.** The author's reasoning: a site's logo is already part of the site itself
(the page the widget is embedded on) — duplicating it inside the support chat window reads as
redundant, not as branding. The widget stays visually part of the host page through color and
launcher position only, not a second copy of the site's own identity.

`11-01` through `11-03`'s scope — primary color and launcher position — is the full, permanent
definition of "widget customization" for Stage 11. The roadmap's "styles/theme" wording is read as
describing what the primary color drives, not a third independent axis.

The other two candidates this item raised (a second color; a light/dark mode toggle) were not
separately addressed by the author and are not decided in or out — they stay genuinely open, unlike
the logo question. Either is cheap to add later as a small extension of `11-01`'s existing fixed-field
`WidgetConfig` pattern, precisely because that pattern was built to be extended (named, validated
fields — never free-form CSS, per `11-01`'s own ADR). Nothing about this resolution forecloses them;
they simply were not asked for now, so no new backlog item is opened for them today.

## Original open question (for context, not active)

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
  operator seeing it first. **Resolved: no — see Resolution above.**
- A **second color** (background, or a text color independent of the primary accent) — a small,
  low-risk extension of `11-01`'s existing fixed-field pattern if wanted, cheap to add later regardless
  of when it's decided. **Not decided — remains genuinely open, revisit if ever wanted.**
- A **light/dark mode toggle**, independent of the primary color — a real design decision (does the
  widget compute contrast against an arbitrary primary color and pick text colors automatically, or does
  the tenant pick a whole named theme) that `11-01`'s two fields do not attempt to answer. **Not
  decided — remains genuinely open, revisit if ever wanted.**
- **Nothing further** — the roadmap's "styles/theme" was loosely worded, and `11-01`'s color +
  position is the intended full scope of Stage 11. **This is the resolution for the logo question
  specifically; the two smaller candidates above are simply not requested today, not ruled out.**

Any answer keeps `11-01`'s own "no arbitrary CSS" constraint — a wider field set is still a wider set of
*named, validated* fields, never free-form styling injected into the shadow tree.

## Done when

- [x] The author has answered the question above (2026-08-23): no logo/avatar. Second color and
      dark-mode remain open but undecided, not blocking anything — no further work item opened for
      either until wanted.

## Open questions

None — resolved.
