# nothing bounds how many times a file is downloaded

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-76` bounds what is stored. This is the other half of the same bill.
- **Found**: 2026-09-07, by pricing the storage quotas rather than by reading code.

## What the prices actually say

Yandex Object Storage, checked 2026-09-07: **2,376 ₽ per GB per month** to store, **1,68 ₽ per GB** to
send out (after 100 GB a month free).

So **a gigabyte costs about as much to keep for a month as to download one and a half times.** Past
that, egress overtakes storage and keeps going.

A support attachment is viewed at least once — by the operator answering — and usually more: reopened,
re-read, shown to a colleague, looked at again when the customer comes back. **The bill will be traffic,
not disk.**

And our quotas bound storage only. The same 100 MB can be downloaded a thousand times, and nothing
anywhere counts it.

## Why this is a gap rather than an optimisation

`23-76`'s ceilings were built against the fear of somebody filling the disk. That fear turns out to be
cheap: 100 MB is a quarter of a rouble a month. **The expensive failure is the one nobody was afraid
of** — a modest amount of data fetched endlessly, which costs real money and looks like ordinary use.

It is also the shape most available to an attacker who has already been stopped by every other control:
they do not need to upload anything. A public-looking presigned URL and a loop is enough, and everything
we built for uploads is silent about it.

## What is not known and must be measured before anything is designed

**How often an attachment is actually downloaded.** Nobody has counted, and inventing the number is
what `CLAUDE.md` forbids. Until it is measured, the sensible ceiling cannot be chosen and the size of
the problem cannot be stated.

So the first half of this item is instrumentation, not enforcement: **count downloads per attachment,
per tenant, per month**, and look before deciding.

## Scope

- **Measure first.** Egress per tenant, per month, from something maintained rather than derived on
  read.
- **Then decide the ceiling**, in the same conversation as the tier grid, because a traffic allowance is
  a priced thing and not an engineering constant.
- **The presigned GET is the leverage point.** Download URLs are already short-lived and issued by the
  API after an authorisation check, so the counting place already exists — this needs no new gate, only
  a number kept at the one it has.

## Where this is likely to go wrong

- **A cache makes the count wrong in the safe direction.** Presigned read URLs are cached per
  (attachment, viewer) for slightly less than their lifetime, and a browser may serve the bytes again
  without asking us. So a count taken at the API undercounts real egress; the storage provider's own
  figure is the truth and ours is a proxy. Say which is which rather than presenting the proxy as fact.
- **Refusing a download is worse than refusing an upload.** An upload that is refused is an
  inconvenience; a download that is refused means a customer cannot see a document they were sent. Any
  ceiling here needs a much gentler failure than the upload side.

## Done when

- [ ] Downloads and outgoing bytes are counted per tenant, and the number is visible to us.
- [ ] The measured figure is written down, so the ceiling is chosen against a fact.
- [ ] Whether there is a ceiling, and what happens at it, is decided with the tier grid rather than here.
