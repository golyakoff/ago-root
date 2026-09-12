# 25-53 · Console-wide audit: "list + create form in one card" becomes two blocks

- **Stage**: 25
- **Status**: done — `ago-console#207`
- **Verified**: 2026-09-12 — confirmed a real, non-trivial set of settings-style pages exists to
  audit: `CalendarServicesPage.tsx`, `CalendarSetupPage.tsx`, `OperatorsTeamPage.tsx`, `TagsPage.tsx`,
  `TeamChatPage.tsx` and others under `src/pages/`. This is an audit item by its own nature — no fixed
  file list to verify against, the audit itself is the deliverable.
- **Depends on**: nothing
- **Found**: 2026-09-12, `feedback.md` — the author has already hand-fixed several screens this way
  and does not remember which; this item is the audit that finds every remaining instance, not just
  the one the feedback names as an example

## What is actually true

Several console settings-style screens use one blended card: a title, then existing objects listed
as plain text (one per line, no way to see count/characteristics at a glance or to edit/delete one
directly), then a create-new-object form below. The feedback's own example is `Записи › Услуги`
(Services): the card shows "Услуги", a plain list of service names, then an add-service form.

## Scope

- **Audit `ago-console` for every screen using this pattern** — not only Услуги. Check every
  settings-style list screen (calendars, allowed origins, webhooks, tags, team members, and any other
  "a list of tenant-owned objects plus a way to add one" screen) for the same one-blended-card shape.
- For every instance found, split into two separate blocks:
  - **A "current items" card**: a real table (name/relevant columns for that object type), with an
    edit (pencil) and delete (cross) action per row.
  - **A separate "add new" card**, below, with the existing create form unchanged in substance.
- An optional filter (the feedback's own example: "Скрыть неактивные") may sit above the list card
  where the object type has an active/inactive concept — do not invent one where none exists.

## Where this is likely to go wrong

- **This is an audit-and-fix item, not a design decision.** The two-block shape is already decided
  (this item's own Scope); the work is finding every place the old shape still exists and applying it
  consistently, not re-litigating the pattern per screen.
- **Don't silently change what a create form submits or what columns exist** — this item changes
  layout and adds inline edit/delete affordances to whatever the object type already exposes on its
  own API; it does not add new fields or new backend capability beyond edit/delete if those don't
  already exist as API operations (if editing an object type has no backend support yet, name that as
  a real gap on the item's own report rather than building new backend surface unannounced).

## Outcome

Three screens found in the old one-blended-card shape, each split into a table card + separate
add-form card:

| Screen | Actions wired | Gap left named, not built |
|---|---|---|
| `CalendarServicesPage.tsx` (the feedback's own named example) | none | no `updateService`/`deleteService` API exists |
| `CalendarSetupPage.tsx`'s calendars sub-section | Edit | no `deleteCalendar` API exists |
| `TagsPage.tsx` | rename-in-place + delete | none — full CRUD already existed |

Already in the two-block shape before this item, unchanged: `CalendarWorkersPage.tsx`,
`OperatorsTeamPage.tsx`. Reviewed and confirmed not an instance of this pattern:
`TeamChatPage.tsx` (a live chat room, not an object list), `CannedResponsesPage.tsx`/
`OfflineAutoReplyPage.tsx`/the calendar setup page's own origins field (each edits one whole list via
a single `PUT`, a different, already-decided pattern — no per-item id), and every single-entity
config screen with no variable-count list at all (`FaqModulePage`, `WidgetConfigPage`, `ProductsPage`,
`DocumentsPage`, the channel pages, `MyNumbersPage`). No webhooks screen exists in the console.

## Done when

- [x] Every console screen using the old one-blended-card list+form pattern is found and listed in
      this item's own Outcome, named by screen, not only the Услуги example.
- [x] Each one is split into a list card (table + edit/delete) and a separate create-form card, using
      the actual object type's own existing fields and API operations.
