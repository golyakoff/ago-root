# the address fields say what shape they expect, and the one that cannot be edited says who to ask

- **Stage**: 23
- **Status**: done (2026-09-06)
- **Depends on**: nothing
- **Decision**: the author's, 2026-09-06 — the placeholder carries the scheme and is translated
  (`https://your.site.ru` / `https://your.site.com`). A fixed `https://` prefix printed beside the
  field was proposed and **rejected by the author**: what a person types is what should be stored.

## What was true

Two screens ask a tenant for their site's address and one shows it back. **None of the three said
what was expected**, and the author hit both halves in one afternoon — they asked whether the field
wants a domain or a full URL, and their own site's allowed origin had to be changed by hand with an
`UPDATE` statement.

## The answer, which is not a preference

**The field wants an origin and cannot want anything else.** The browser sends
`Origin: https://shop.example`, and the comparison is literal (`5-01`, layer 2), so a bare domain
matches nothing.

What makes that expensive is *how* it fails: the widget **silently never connects**. Everything looks
configured — the console shows a key, a snippet, an address — and nothing works.

## Why the example became a translated string

`OnboardingPage`'s own comment argued the opposite, and it was half right. A `placeholder` attribute
is **not** a DOM text node that `ux-gate`'s untranslated-text assertion, or a screen reader, ever
sees — so no gate would have caught this, ever.

The second half was wrong. **The example's own top-level domain is the part that tells a reader which
kind of address is wanted**, and a `.com` in a Russian form reads as somebody else's example rather
than a shape to copy. Being invisible to the gate made it *more* worth changing by hand, not less.

## The address that cannot be edited

**There is no editor for a chat tenant's allowed origin anywhere in this console.** `5-01` deferred
one; nothing has built it since. The install screen shows the value and nothing said it was
read-only, so a tenant reading an address that is wrong had **no next step at all**.

The panel description does mention getting in touch — inside a conditional about going live, three
lines above the value. Somebody looking at the address never reaches it. That is how the author's own
site came to be fixed with a hand-written `UPDATE`.

The hint sits **beside the value**, and the test asserts the placement rather than only the words.

## Done when

- [x] Both fields that ask for an address show an example carrying the scheme, in the reader's own
      language.
- [x] The address the install screen shows says how to change it, next to the value.
- [x] Each half fails on its own against the old code.

## Out of scope, and filed separately

**An editor for the allowed origin.** This item makes the absence honest; it does not remove it. That
a tenant cannot change their own site's address without asking us is a real gap, and it gets its own
number rather than being carried inside a finished item.
