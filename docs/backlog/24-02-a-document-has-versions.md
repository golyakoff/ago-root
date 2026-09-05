# a document has versions, and a person can read the one they accepted

- **Stage**: 24
- **Status**: done (2026-09-05). Documents, versions, an owner-gated publish and an unauthenticated read; `adr/0114` for why the text is data.
- **Depends on**: `24-01` — the version identifier an acceptance points at has to point at something.
- **Decision**: none yet; the publication obligation is `152-ФЗ` art. 18.1 п. 2, cited for orientation
  rather than as legal advice, the same way `personal-data.md` cites the localisation rule

## Goal

Every document a person can accept is published, carries a version, and stays readable in the version
they accepted — including after it changes.

## Why this is separate from `24-01`

`24-01` answers *what can we prove*. This answers *what can they read*. A record pointing at
"v3 of the privacy policy" is worthless if v3 no longer exists anywhere, and a published current text
is not evidence of what somebody agreed to last year. Two promises, and each lands green alone.

## What is actually true today, verified

- The tenant supplies the widget's processing-notice text and a link to their own document
  (`16-04`, shipped). **That is the tenant's document, not ours**, and this item does not take it over.
- AGO publishes no document of its own that a person can point at. `personal-data.md` is an engineering
  register in a public repository — it is not, and must not be mistaken for, a published policy.

## Scope

- A version identifier that is stable, ordered and human-quotable, so a support conversation can say
  "you accepted v4 on 12 March" and both sides can look at the same text.
- The published surface: where a person reads the current text without signing in, since somebody who
  has not yet accepted anything has no account to read it from.
- **Old versions stay reachable.** A superseded version is not deleted; a person who accepted it can
  still read what they accepted.
- Where the text itself lives, and how a change to it reaches production. The text is `ago-business`'s
  and a lawyer's; the mechanism is ours. Say plainly which repository holds which.

## Out of scope

- Writing any legal text. Not ours, and inventing a default is worse than having none — the same
  reasoning `16-04` applied to the tenant's own notice.
- Deciding which documents exist at all. That falls out of `24-03`, `24-04` and `24-05`.
- The tenant's own visitor-facing document. Theirs.

## Done when

- [ ] A document has a version identifier that an acceptance record can point at.
- [ ] The current version is readable without an account.
- [ ] A superseded version is still readable, and a test proves publishing a new one does not remove it.
- [ ] Changing the text is a described procedure with a named owner, not an edit somebody makes.

## Open questions

- **Does a new version invalidate an existing acceptance?** Sometimes it must and sometimes it must
  not, and the difference is what changed. This needs a rule rather than a judgement each time — and
  the rule belongs with the lawyer's reading, since re-obtaining consent unnecessarily is itself a cost.

## Outcome

**The item asked where the text lives to be answered rather than assumed, and the answer changes how
this stage proceeds.** The text is **data in Postgres**, published through one owner-gated call. No
legal text is committed to this public repository at all.

That was decided against a live constraint: the author sequenced this stage as *build the mechanism
now, have a lawyer validate the text afterwards*. That only works if a lawyer's verdict is a change to
**data**. It now is — a wording fix, a new version, or a whole new document is one authenticated HTTP
call, never a commit, a PR and a deploy.

**Neither `Document` nor `PublishedDocumentVersion` has a rename, an update or an edit method.**
Checked by grep at review rather than taken from the report. So "a correction is a new version" holds
by the shape of the types, not by anybody remembering.

**The version identifier is server-derived**, `v{n}` from the aggregate's own counter. That is the only
form that is stable, ordered and human-quotable at once — a support conversation says "you accepted v4
on 12 March" and both sides open the same text. A hash is stable and unquotable; a timestamp is ordered
and unmemorable; a caller-supplied string is neither guaranteed.

**A found bug, not a designed one.** The concurrent-publish test first collided on the unique index
instead of the concurrency token, because EF inserts `Added` rows before `Modified` ones — the same
failure `23-04` found for `conversation_assignments`, handled the same way. It was found by forcing the
race through a second real commit rather than a fabricated exception, which is why it surfaced at all.

**One of three migrations built in parallel in `ago-chat`**, the first time that has been permitted.
The safety that makes it work is not care but `dotnet ef migrations has-pending-model-changes`, which
reports a snapshot that has lost a table even when that snapshot still compiles — demonstrated on a
deliberately damaged copy before the arrangement was relied on.
