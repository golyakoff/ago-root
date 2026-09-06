# one console screen prints an unlabelled local time, against the project's own convention

- **Stage**: 11
- **Status**: closed as duplicate (2026-09-03), fourteen minutes after filing — absorbed into `11-17`
  (`ago-root#343`) the same day. **Written retrospectively on 2026-09-06**; see `23-49`.
- **Found**: 2026-09-03, by `11-16`'s new gate assertion.

## Written retrospectively, and why this file is thinner than the others `23-49` reconstructs

`ago-root#344` was open for fourteen minutes. It was never implemented under its own number, so there
is no commit, no test, and no design choice made in its name to recover. **This is not a gap in the
reconstruction — it is the true shape of what happened**, and the honest record says so rather than
inventing an implementation history this item never had.

What follows is the issue's own text, kept because it is the only surviving statement of the defect,
plus where the actual fix lives.

## What the issue said

`src/pages/AdminConversationsPage.tsx` line 90:

```tsx
render: (c) => <span className="ago-meta">{new Date(c.createdAt).toLocaleString()}</span>
```

It bypassed `src/time/format.ts` entirely — the one place in the gated screen set that routes dates
through a single formatter. `time/format.ts`'s own header warned against exactly this construct:
*"`toLocaleString()` with no zone label at all."* A bare `toLocaleString()` renders in whatever zone
the runtime happens to be in, with nothing saying which — `docs/conventions/date-and-time.md` requires
the user's IANA zone when supplied and otherwise UTC labelled as UTC. On the screen where an operator
inspects conversations, that is a timestamp nobody can interpret, not merely an untranslated one. It
also rendered `AM`/`PM` under the gate's Chromium, which is how the assertion in `11-16` found it.

Filed narrower than the sibling item found the same hour, `11-17` (`ago-root#343`, "the console shows
dates wrong: English words, and one screen with no zone label at all") — different cause, arguably
worse, and about the same screen.

## Why it was closed as a duplicate rather than implemented

`CLAUDE.md` rule 15 was written from this pair on 2026-09-03, the same day. `11-18` and `11-17` had
been split on a code-level test — different files, neither calls the other — which the rule now names
as the wrong test: they are **one promise**, "the console shows dates correctly," and fixing only one
half would have left `11-16`'s gate red on `admin-conversations`. `11-17`'s own issue body records the
widening explicitly: *"Widened 2026-09-03 to absorb `#344`... They are one promise... and it shows:
fixing only the first half leaves `11-16`'s gate red."*

So `11-18` was closed as a duplicate and its fix shipped inside `11-17`'s own commit.

## Where the actual fix lives

`ago-console` commit `8d829c8` — `fix(11-17): the console shows dates in the language it is set to` —
includes `AdminConversationsPage` explicitly rather than splitting it off, for the reason quoted above.
Its commit message states the same rejection this issue's own "out of scope" note anticipated: doing
the two together, not in sequence, because rule 15's test is one promise landing green.

**No commit in any repository names `11-18`.** The queue's own audit (`23-49`) confirmed this by
searching every repository's history; the search here found the same. The item's number appears
nowhere except this file, the closed issue, and `23-49`'s own count.

## Out of scope

- Re-implementing anything — the fix already shipped, under `11-17`. See that item's own file
  (`docs/backlog/11-17-the-console-reports-every-post-callback-failure-as-sign-in.md`) for the
  process note: `11-17`'s number is itself shared by two closed issues (`ago-root#383` and
  `ago-root#343`), a pre-existing collision `22-21` chose to leave alone because both sides had
  already shipped under that tag — not something this item reopens.

## Done when

- [x] The record exists: what the issue said, why it was closed as a duplicate, and where its fix
      actually landed.
