# the tenant can tell their visitors what the widget puts on their device

- **Stage**: 24
- **Status**: done (2026-09-06)
- **Depends on**: nothing. `24-05` is adjacent — it settles what a visitor *consents* to; this settles
  what the tenant must be able to *declare*.
- **Decision**: `docs/design/decisions.md` §10's audience reasoning applies by analogy; the storage
  facts are `adr/0029` and the `embeddable-widget` skill

## Goal

A tenant putting our widget on their site can say, in their own cookie or privacy notice, exactly what
it stores on a visitor's device, why, and for how long — without reading our source.

## The first fact changes the shape of this item, so it goes first

**We set no cookies. Not one.** Verified 2026-09-05: `ago-widget/src/connection.ts` and `src/storage.ts`
both record it as a deliberate decision citing the `embeddable-widget` skill — *"No cookies on the host
domain, no fingerprinting, no reading anything the host page put in storage"* — and the connection
explicitly disables the transport default that would have sent the host's cookie jar. `ago-chat` sets
none either.

So a ticket called "add a cookie banner" would be answering a question we do not have. **What we
actually do is `localStorage`**, under keys prefixed `ago-chat:<siteKey>:`, which by construction can
neither collide with the host page's own storage nor read a key the widget did not write.

**That does not make the obligation go away**, and this is the part worth being precise about. The
stored record holds a **`visitorId` and a session token** alongside cached widget appearance. The
identifier is what makes a returning visitor recognisable across visits — it is renewed rather than
re-minted (`17-07`), precisely so one person does not fragment into many. A persistent identifier for
a person is the interesting half; the cached colour beside it is not.

## Why this is the tenant's declaration and not ours

The widget runs **on the tenant's domain**, inside the tenant's own relationship with their customer.
`adr/0076` makes AGO the processor there and `16-04` already established the shape: AGO supplies the
mechanism, the tenant owns the words. Their banner or privacy notice is where this is declared, and
today **they have no way to learn what to declare** — the facts exist only in our source.

A tenant who lists "cookies: none" because they checked their own cookie jar would be accurate and
still incomplete.

## Scope

- **A document, in the tenant's own console**, listing every key the widget writes: its name, what it
  holds, why it is there, how long it lives, and whether it survives the visitor closing the tab.
  Written for somebody drafting a privacy notice, not for a developer reading a schema.
- **Stated plainly that these are not cookies**, because a tenant auditing their site for cookies will
  otherwise miss them entirely — and so will their auditor.
- **The retention answer must be real.** Say what actually clears the record: token expiry, renewal,
  the visitor clearing site data. If nothing expires it, say that.
- **`personal-data.md` gains a row for it.** A `visitorId` on a visitor's own device is data held about
  a person, in a place the register currently does not describe at all — it inventories our stores, and
  this one is on somebody else's machine.

## Out of scope

- **Writing the tenant's banner text, or shipping a banner.** Same boundary as `16-04`: their words,
  their relationship, their site. A banner injected by our widget onto somebody else's page would also
  be the over-reach `decisions.md` §10 argues against in a different context.
- **Changing what the widget stores.** If the review finds something that should not be there, that is
  a finding and its own item, not a quiet edit.
- **Whether the visitor must consent before it is written** — see the open question. This item makes
  the facts available; `24-05` owns the consent question.

## Done when

- [x] A tenant can read, from the console, every key the widget writes and what each is for.
- [x] The document says these are not cookies, in those words.
- [x] Each entry states its lifetime, including the honest answer where nothing expires it.
- [x] `personal-data.md` carries the row, including that this store is on the visitor's own device and
      what that means for erasure — we cannot reach it, and the register should say so rather than
      imply we can.
- [x] A test asserts the documented key set matches what the widget actually writes, so the document
      cannot drift from the code the way `16-02`'s own remarks did.

## Open questions

- **Does writing the identifier need consent, or is it necessary to the service the visitor asked
  for?** Opening a chat and expecting a reply arguably requires recognising the same person on the next
  page — which is the "strictly necessary" argument. `24-05` found the analogous answer for contact
  details: consent attaches to the act, not to using the product. The same reasoning plausibly applies
  here, and plausibly is not good enough. Needs the author, and probably the lawyer already engaged for
  `24-04`.

## Outcome (2026-09-06)

`ago-widget` `39d5286`, `ago-console` `95a188d`.

**The item's own first fact held up, and it changed the shape of the answer.** We set no cookies —
verified again at implementation, including that the transport default which would have sent the host
page's cookie jar is explicitly disabled. So the deliverable is not a cookie banner; it is a
disclosure of `localStorage`, which a tenant's cookie audit will not find.

**`WIDGET_STORAGE_DISCLOSURE` in `ago-widget/src/storage.ts` is the single source.** The console
screen renders it and its test asserts against it, so the document cannot drift from the code — which
is what the fifth Done-when asked for, and the failure `16-02`'s own remarks had already suffered.

**`personal-data.md` gained the row, and it is the only row in that register where AGO has no erasure
path at all.** That is stated rather than softened: `16-02`'s erasure does not reach a visitor's own
device and no future job can. What clears an entry is the visitor clearing their site data, or each
key's own replacement rule. A register that implied otherwise would be wrong in the direction that
matters.

**A fifth forcing place was added, because the existing four could not have caught this.**
`personal-data.md`'s "Keeping this true" named `data-model.md`, the `db-migration` skill and the
`messaging-contract` skill. All three guard data landing in *our* stores. A key written to somebody
else's device passes no migration, no contract and no schema review, so the widget's storage was the
map's blind spot rather than an entry nobody had got round to. `.claude/skills/embeddable-widget` now
names the register, in its own Storage and privacy section.

**The open question is untouched and still the author's** — whether writing the identifier needs
consent or is strictly necessary to the service the visitor asked for. This item made the facts
available, which is what a lawyer needs to answer it; `24-05` owns the consent question itself.
