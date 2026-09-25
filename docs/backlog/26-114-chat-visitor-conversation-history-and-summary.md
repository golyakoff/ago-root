# 26-114 · [chat] A visitor's conversation history + summary on this site (list, count, first-seen)

- **Stage**: 26 — implementation of `26-111` (design: `docs/design/26-111-thread-contact-detail-panel.md`).
- **Status**: ready — direction fully decided (26-111 author decisions #3, #4, #5).
- **Depends on**: nothing (backend-only; unblocks the Android summary + past-dialogs clients later).

## What and why

The contact-detail panel's header needs «Первый визит {date} · N диалог(ов)», and «Прошлые диалоги» needs
the list of this visitor's other conversations — **for every visitor, including widget-only ones with no
channel identity** (author decision #3: the row must never be dead). Today visitor history is gated on
channel identity, and there is no first-seen / conversation-count on any wire DTO.

## Scope (one promise: the backend exposes a visitor's conversations on a site, safely)

- A read endpoint returning, for the conversation's visitor **scoped to the site**:
  - `firstSeenAt` (from `Visitor.FirstSeenAt`, already stored),
  - `conversationCount` = **distinct conversations of this visitor on this site, including the current
    one** (author decision #5),
  - the **list** of those conversations (id, started-at, last-message preview, state) for «Прошлые
    диалоги», ordered newest-first, read-only (no assignment/takeover implied).
  - Shape it so the header summary and the list come from the **same scope** (the count always equals the
    list length) — one endpoint returning summary + a page of the list, or a summary endpoint plus a list
    endpoint that share the exact scoping query. Decide and document which.
- **Widen the scope off channel-identity to per-visitor-on-site.** This is an authorization/privacy-boundary
  change → write an **ADR** (amending the current channel-identity gating; pre-assigned number: **ADR-0182**
  — put the row text in your report, do NOT edit `docs/adr/README.md`) and update
  `docs/architecture/personal-data.md` to state the new boundary.
- Gate by the same permission the panel uses to read a conversation (`conversation:read`); a visitor's
  history is visible to an operator who may read that visitor's conversation.
- If (and only if) a schema change is genuinely required, it goes through the **migration lane** — but this
  is expected to be a query/scope change with **no migration** (all columns exist). Confirm and say which.

## Out of scope

- The Android clients for this (separate tickets).
- Any name-assessment / «Недействительно» (dropped, decision #1).
- Changing how a conversation is assigned or read beyond exposing the history.

## Done when

- [ ] The endpoint(s) return firstSeenAt + conversationCount + the conversation list for a visitor scoped
      to the site, count == list scope, for widget-only visitors too.
- [ ] ADR-0182 written (row reported, not committed to the index) + `personal-data.md` updated.
- [ ] `dotnet format` / build (0 warnings) / full test suite green, counts reported; a test proves a
      widget-only visitor with multiple conversations gets them all, and the count matches.
