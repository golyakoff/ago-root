# a tenant cannot change their own site address without asking us

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-46` made the absence honest; this removes it.
- **Decision**: none needed for the gap itself. One question inside it is the author's, below.

## What is actually true

A chat tenant's `allowed_origins` is set **once**, at signup, and after that **nothing in this
console can change it**. `5-01` deferred the editor — its own scope says so — and nothing has built
one since. `20-06` built one for AGO Calendar; chat never got the equivalent.

The install screen shows the value read-only. `23-46` added a line under it saying to contact
support, which is honest and is not a fix.

**Found the ordinary way**: the author's own site had the wrong address, and it was changed with a
hand-written `UPDATE` against the live database, followed by a manual Redis delete — because the site
config is cached cache-aside, so the row alone would have kept the old origin for as long as the
entry lived.

## Why it costs more than it looks

- **It is the one setting that silently breaks everything.** A wrong origin means the widget never
  connects, on a page that otherwise looks correctly configured. `23-06` and `23-07` exist to tell a
  tenant that their widget is not arriving; this is the most likely reason, and the console offers no
  way to act on it.
- **A shop moves domain.** Adds `www.`, moves to a subdomain, gets a new one entirely. Today every
  one of those is a support request that ends in somebody typing SQL against production.
- **Typing SQL against production is the actual risk here**, not the inconvenience. The manual fix
  needs the right row, the right array syntax, and a cache invalidation nobody would guess at from
  the schema. It worked because the person doing it wrote the caching.

## Scope

- An editor on the install screen (or beside it), gated by the same permission every other tenant-wide
  setting uses.
- **Server-side validation that an entry is an origin** — scheme and host, no path, no trailing slash
  — refusing rather than storing something that can never match. `20-06`'s calendar-side equivalent
  already rejects `'https://shop.example/booking' is not an origin`, and its wording is worth reusing.
- **Cache invalidation in the same path as the write**, both keys (`site-config:{publicKey}` and
  `site-config:id:{siteId}`), because a save that appears to work and takes effect an hour later is
  worse than one that refuses.
- A test that the widget's own origin check honours the new value without a restart.

## The question inside it, which is the author's

**Who may change it?** Two readings, and they differ in what a support request is for:

- **The tenant themselves**, under `site:configure` like every other tenant-wide setting. Fewest
  support requests. But the allowed origin is the one field where a typo silently kills the product
  for that tenant, and they will not see the consequence until a customer does not appear.
- **The platform owner only**, from `/owner`, with the tenant still asking. Keeps a second pair of
  eyes on the field most likely to be wrong, at the cost of every domain move being a ticket.

A third shape exists — the tenant edits, and the console *shows them* whether the widget has been seen
at the new address since the change (`23-06` already records the sighting) — which turns the silent
failure into a visible one and makes the first reading much safer. It is more work.

## Done when

- [ ] The author has chosen who may edit it.
- [ ] A tenant's site address can be changed without anyone writing SQL.
- [ ] A value that is not an origin is refused with a message naming what is wrong with it.
- [ ] The change takes effect immediately, proven against the cache rather than assumed.

## Out of scope

- The calendar's own allowed-origin editor, which exists (`20-06`).
