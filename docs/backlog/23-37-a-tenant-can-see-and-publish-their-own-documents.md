# a tenant can see and publish their own documents

- **Stage**: 23
- **Status**: ready, **narrowed 2026-09-06** after the author corrected what this item assumed.
  It is the tenant's *own* documents only; the two other audiences below are `23-52` and a question.
- **Depends on**: `23-31` reserves the place (Администрирование → Документы). `24-02` built the store.
- **Decision**: `adr/0114` — a document's text is data; only publishing and reading it is code

## Goal

The tenant whose consent text a visitor is asked to accept can read it, change it, and see which
version people accepted.

## What is actually true today, found while drawing the navigation

**`24-02` built documents and versions, `24-05` made visitors accept them, and there is no screen.**
A tenant publishes their own consent text through an API call. Nothing in the console shows what is
published, what version is current, or what a person accepted.

`24-03` compounds it: `required_documents` decides which documents bind which subject kind, and it
**ships empty in every deployment** — so today a registration records zero acceptances and succeeds.
That is `24-16`'s subject, and this item is the surface a tenant would use to notice.

## Why the mechanism was built this way, and why the screen completes it

`adr/0114` made the text **data** precisely so a wording fix is one call rather than a commit, a PR
and a deploy — which is what makes the author's own sequencing work: build the mechanism now, have a
lawyer validate the words afterwards. **A lawyer's verdict changes a row.** Without a screen, it
changes a row that only somebody with a terminal can reach, which puts an engineer in the middle of
every legal correction.

## Scope

- List the tenant's documents and their versions, newest first, with when each was published.
- Publish a new version. Versions are server-derived `v{n}` and a correction is structurally a new
  version, never an edit — `adr/0114` has no rename, update or edit method at all, on purpose.
- Show what was accepted: `acceptance_records` already holds subject, document key, version and
  instant. A tenant asked *"prove they agreed"* should not need us.
- Read a published version as a visitor would, so a tenant can check the words in place.

## Out of scope

- Writing any legal text. `16-04`'s boundary, unchanged: AGO supplies the mechanism, the tenant owns
  the words.
- Making a document **required** — that is `24-16`, and it is the half that decides behaviour rather
  than showing it.

## Done when

- [ ] A tenant sees their documents and every version, with dates.
- [ ] Publishing a new version works from the console and the old version stays readable.
- [ ] A tenant can answer "which version did this person accept, and when" without asking us.
- [ ] Nothing in the console offers to edit a published version in place.

## The author's correction, 2026-09-06 — and it is not a detail

This item was filed believing *documents* meant one thing: the consent text a **tenant publishes to
their own visitors**, which is what `24-02` and `24-05` actually built.

The author's reading is wider, and closer to what a real account needs:

| Who writes it | Who reads it | Example | Where it stands |
|---|---|---|---|
| **AGO → the tenant** | the tenant | договор, соответствие безопасности | **nothing exists.** `23-52` |
| **the tenant → their clients** | a visitor | consent text | built (`24-02`/`24-05`), no screen — **this item** |
| **the tenant → their operators** | an operator | *maybe* — the author says *может быть* | not decided, see below |

**The first row is the one that changes plans.** Those documents *"должны автоматически создаваться при
регистрации теннанта"* — so they are not a screen at all, they are part of what a registration
produces. A tenant who signs up today gets an account with **no contract on it**, and nothing in this
queue said so until now. That is `23-52`, and it outranks this item.

**Why they are separate tickets and not one.** They make different promises with different actors and
different lifecycles: one is *we place our terms on their account when it is created*, the other is
*they publish their words to their visitors*. Rule 15's test - would closing one leave the other
broken - says no, both land green alone. And one screen listing all three would have to answer *who
may publish this kind* three different ways.

**The third row is a question, deliberately left open here.** A document from a tenant to their own
operators has no reader in this system yet: an operator accepts nothing at sign-in today (`24-04` is
the item that would change that), so a document with no acceptance path is a file, not an agreement.
It is worth having *after* `24-04`, and worth nothing before it.
