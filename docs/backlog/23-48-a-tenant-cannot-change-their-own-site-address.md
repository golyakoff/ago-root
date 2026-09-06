# a tenant cannot change their own site address without asking us

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. `23-46` made the absence honest; this removes it.
- **Decision**: the author's, 2026-09-06 — **only the platform owner may edit a tenant's site address.
  Nobody else.** The question this item held open is answered; the surface it lives on is sketched.

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

## The answer (author, 2026-09-06)

**Only the platform owner may edit it, for any tenant. Nobody else — not even the tenant.**

That is the second of the two readings this item offered, and it takes the cost the first was trying
to avoid: every domain move becomes a request to us. Worth naming what it buys, because it is not
caution for its own sake — **this is the one field whose typo silently kills the product for that
tenant**, and they will not see the consequence until a customer fails to appear.

**It also collapses the sketch this item offered as a third shape.** Showing the tenant whether the
widget has been seen at the new address was only needed to make *tenant-edits* safe. With the owner
editing, the person making the change is the person who can read the install screen anyway.

## Where it lives, which the author sketched rather than settled

*«может быть в списке клиентов — там же где теннант будет подключать каналы вручную и менять квоты»*

`/owner` already lists every site and already has a per-tenant detail screen. So this is a field on a
screen that exists, not a new place — and it lands beside two other things the same page is going to
want for the same reason: **manual channel connection** and **quota changes**, both of which are
today either a runbook or a database statement.

That is a pattern rather than three coincidences: *the platform owner's own maintenance surface*.
Worth noticing while building this one, and worth **not** building the other two inside this ticket —
they are separate promises with their own arguments (`23-36` already owns channels).

## Done when

- [x] The author has chosen who may edit it — the platform owner, and nobody else.
- [ ] A tenant's site address can be changed without anyone writing SQL.
- [ ] A value that is not an origin is refused with a message naming what is wrong with it.
- [ ] The change takes effect immediately, proven against the cache rather than assumed.

## Out of scope

- The calendar's own allowed-origin editor, which exists (`20-06`).
