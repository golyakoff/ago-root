# Canned responses

- **Stage**: 18
- **Status**: done (2026-08-29, `ago-chat#119` + `ago-console#58`) — see Outcome below
- **Depends on**: nothing

## Goal

An operator inserts a prepared answer instead of typing the same thing for the fortieth time. Per site,
editable by whoever can already configure the site.

## Context to read first

`docs/backlog/14-04-offline-auto-reply.md` — it already introduces per-site scripted replies keyed by
phrase, and this item should reuse that shape rather than invent a second store of canned text with
different rules. If `14-04` has landed, the question is whether these are one concept with two entry
points (a human picks it, or the system sends it when nobody is online) or genuinely two; answer that
before adding a table. `adr/0016`'s RBAC — `site:configure` already gates this class of setting.
`docs/backlog/11-05-console-design-foundation.md` — the components this screen is built from.

## Scope

- Per-site canned responses, editable in the console behind the permission that already exists.
- Insertion into `11-06`'s composer, by keyboard rather than only by mouse — the point of the feature
  is speed, and a shortcut that requires a click is not that.
- A decision, stated: one concept shared with `14-04`'s scripted replies, or two. Reuse if it is one.

## Out of scope

- Placeholders and substitution (visitor name, order number). A real want, and a real templating
  decision with escaping consequences; separate item once someone asks.
- Per-operator personal snippets. Per-site first; personal ones are a different ownership model.
- Anything about the offline auto-reply's own triggering (`14-04`).

## Done when

- [x] Responses are editable per site, gated by `site:configure`.
- [x] An operator inserts one without leaving the keyboard.
- [x] The shared-or-separate decision against `14-04` is recorded.

## Open questions

None.

## Outcome

Shipped as `GetCannedResponsesHandler`/`UpdateCannedResponsesHandler` (`ago-chat#119`) plus a settings
screen and composer picker (`ago-console#58`). **Decided: two small, honest types, not one shared with
`OfflineAutoReplyRule`** — the shapes are similar at rest, but the access pattern differs: an auto-reply
is matched against visitor text automatically, with no human in the loop; a canned response is browsed
by an operator's own eyes and picked, with nothing ever compared against message text. Forcing one type
to serve both would mean a dead `Keyword` field on canned responses or a `Title` the auto-reply matcher
never reads — recorded in `CannedResponse.cs`'s own remarks. Keyboard insertion: typing `/` as the first
character of the composer draft opens a filterable picker (title match), `↑`/`↓` to highlight, `Enter`
to insert and close — the same interaction convention independently proposed for the visitor-facing
`20-07` module-invocation design during planning (`docs/backlog/20-07-*.md`'s own "Decided in planning"
section), not shared code between the two (different apps) but a deliberate, repeated UX choice.
