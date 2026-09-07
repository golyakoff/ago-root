# the first file that is not what it claims closes the door

- **Stage**: 23
- **Status**: **not now, deliberately** — recorded so it is not rediscovered, not scheduled.
- **Depends on**: `23-78`, whose grant this would revoke automatically. Meaningless without it.
- **Found**: 2026-09-07, the author's idea, filed at their request as one we are not taking yet.

## The idea

Every type this product accepts has a fixed signature in its first bytes — `%PDF-`, PNG's eight-byte
header, JPEG's `FF D8 FF`, GIF's `GIF8`, WebP's `RIFF….WEBP`. A declared content type is a claim by the
client; the leading bytes are the file itself.

So: **if the first file a visitor sends does not begin the way it claims to, close the upload door**
until an operator opens it again by hand (`23-78`'s grant).

## Why it is worth keeping

It is not a virus scanner, and that is its virtue. It answers one narrow question — *is this the kind
of thing it says it is* — with a comparison of a few bytes, no library, no vendor, no false-positive
model. Something disguising a payload as a PNG fails it on the first attempt, and the punishment is not
a refusal of that file but the loss of the ability to send any, which is a much more expensive outcome
for whoever was probing.

`file-storage.md` already admits the adjacent gap: content type is *"sniffed from the first bytes
server-side for images"* in the design and **not actually shipped that way** — the HEAD verification
trusts whatever the store recorded. So the sniffing this needs does not exist yet either.

## Why it is not now

- **`23-78` has to exist first.** Without a grant to revoke, the heuristic has no consequence to apply.
- **The bytes are not in our hands.** Uploads are presigned and go straight to storage, so reading the
  first bytes means either fetching the object back after the fact — after it is already stored, which
  is the cost we were trying to avoid — or moving uploads through the API, which `adr` and
  `file-storage.md` deliberately do not do. **That is the real obstacle, and it is not small.**
- **It is a second-order defence.** The allowlist already refuses anything that is not an image or a
  PDF by declared type, and `23-78` already stops an unagreed upload. This catches the case where
  somebody was granted permission and then abused it — real, but rarer than what is already covered.

## If it is ever taken

- Compare against the **declared** type, and treat "cannot tell" as a pass. A heuristic that guesses is
  worse than one that abstains.
- Revoking the grant is the punishment; deleting the file is a separate decision with its own record.
- Say nothing useful to the sender. "Rejected: bad magic bytes" is a tutorial.

## Done when

Not scheduled. This section exists so that whoever picks it up knows the obstacle above is the thing to
solve first, rather than rediscovering it after writing the byte tables.
