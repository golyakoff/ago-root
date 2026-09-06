# the platform owner is shown no demo band at all

- **Stage**: 23
- **Status**: done (2026-09-06). One condition in `PublicDemoNotice`, and the owner wording deleted
  with the branch that read it.
- **Depends on**: nothing. Narrows `12-04`, which narrowed `8-06`.
- **Decision**: the author's, 2026-09-06 — *«я знаю кем вошёл, я не хочу это видеть»*

## Goal

The platform owner opens the console and sees the console.

## What was there, and why it is a decision to remove rather than a deletion

`8-06` put a permanent band on every screen of the public demo console: *this is public, the login is
published, the conversations are strangers', do not type anything real.*

`12-04` gave it a second wording, and its reasoning was good: *"its login is published on the demo
pages, so anyone can sign in here"* is **false** of the platform owner's account — published nowhere,
held by one person — and **a standing disclosure a reader can personally verify as wrong teaches them
the whole strip is boilerplate.** So it corrected the false clause and deliberately kept the one true
of everybody: the conversations are strangers', nothing real goes here.

## What actually changed, which is not that reasoning

`12-04` was reasoning about a **class** of reader. This class has **one member.**

He knows every fact in the sentence, has read it every day for a fortnight, and cannot dismiss it.
For that reader the band is furniture: it costs a line of vertical space on every screen and trains
the habit of not reading banners — **which is the exact failure `12-04` was avoiding, arrived at from
the other direction.** A disclosure is for someone who might not know.

## The boundary, because this is the part that could go wrong later

**It is a removal for one identity, not a softening for anybody.** Untouched:

- the shared demo login, whose login *is* published — where the band was actually load-bearing,
  against an operator treating a public queue as their own sandbox;
- every reader not yet identified;
- every pre-session screen.

**The failure direction is untouched too.** `"unknown"` and `"ineligible"` both still produce the
strict text, so a probe that has not answered yet, or a route added later that never learns about the
prop, shows *more* rather than nothing. Three of the four tests in `demoNotice.test.tsx` exist to keep
this from widening and would redden if it did.

## Two consequences worth having on the record

**`publicDemoNoticePlatformOwner` is deleted from all three i18n files**, and the ternary that read it
collapses to one string. The branch is unreachable now, and a wording nothing renders is exactly the
stale artefact somebody cites a year later as if it shipped.

**A dismissible band was the alternative and lost.** It needs somewhere to remember the dismissal, and
browser storage is per-device and empty in a private window — so the owner would meet it again on
every new machine, which is most of the complaint. For an audience of one whose identity the server
confirms on every page, not rendering it is simpler *and* more reliable than remembering it was
closed.

## Done when

- [x] The platform owner sees no band on any screen.
- [x] The shared demo login, an unidentified reader and every pre-session screen see it unchanged,
      asserted rather than assumed.
- [x] The unreachable wording is deleted rather than left in the locale files.
- [x] A probe that has not answered yet still shows the strict text.

## Out of scope

- Whether the band's wording is right for the readers who still see it. `12-04` settled that and
  nothing here reopens it.
