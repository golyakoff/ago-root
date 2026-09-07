# a visitor is talking to a person and cannot see one

- **Stage**: 23
- **Status**: ready. The three product questions were answered by the author on 2026-09-07 and are
  recorded below; one assumption is named rather than buried.
- **Depends on**: `24-04` (the operator's own lawful basis and what they are shown at first sign-in)
  is the natural place for the consent this needs. It is open. See "The dependency worth arguing about".
- **Decision**: the author's, 2026-09-07 — an operator has a photo and the visitor sees it. Their
  framing is the point: *now that personal data is handled properly, functionality stops being cut out
  of fear of handling it.*

## What is actually true today

A visitor writes into the widget and a person answers. The widget shows that person's **name**, and
nothing else. The transcript is a wall of text with no face in it.

Every product this competes with shows a photo, and not for decoration: a photograph is the cheapest
signal a visitor gets that somebody is actually there. A shop's own customers decide whether to keep
typing in the first fifteen seconds, and "a real person, with a face, called Pavel" is a different
proposition from "a name".

## Scope

- **An operator has a photo.** They upload it themselves, in the console, on their own profile. Not
  the tenant's admin uploading photographs of their staff — that is a different consent story and a
  worse one.
- **The widget shows it**: in the header, beside the operator's name and role, and beside their
  messages in the transcript, so a long conversation still reads as coming from that person.
- **There is a graceful absence.** Most operators will have no photo on day one and some will never
  want one. Whatever stands in its place must look deliberate rather than broken — and must not be a
  generic silhouette that reads as "user not found".
- **The bytes go to object storage, not the database**, through the existing presigned-upload path
  (`docs/architecture/file-storage.md`) — attachments already work this way and an avatar is smaller
  than every one of them.
- **A photo is deleted when the operator is**, and that is testable rather than assumed.

## The personal-data work, which is the actual content of this item

An operator's photograph is **personal data about the operator**, and unlike a visitor's contact
detail it is data we ask a member of our tenant's staff to hand over so that strangers can look at it.
That is not a reason to refuse it. It is a reason to do it once, properly, and write down what was
done:

- **The lawful basis is consent, and consent must be refusable without consequence.** An operator who
  declines a photo must lose nothing — no degraded screen, no nag on every sign-in, no implication
  that the tenant will be told. `24-04` is where an operator is told what we hold about them; this is
  a second thing to tell them there.
- **`personal-data.md` gains a row**: what is held, where, on what basis, and how it is removed. Today
  that document knows nothing about operator photographs.
- **Retention on departure.** A deactivated operator's photo should not survive them. `22-08`
  (tenant lifecycle) and `24-12` (the tenant's own access record) are the neighbours here.
- **What a visitor keeps.** A transcript is retained. If a visitor's saved transcript renders the
  operator's photo, then deleting the photo does not delete every copy of it — decide whether the
  widget renders a stored URL or resolves it live, and say which, because they behave differently the
  day somebody asks to be removed.

## The three questions, answered by the author 2026-09-07

The three answers turn out to be one design, so they are written together rather than as a list.

**A tenant holds stand-in portraits, and they are AI-generated.** The author's reasoning: a generated
portrait uses nobody's likeness, so the tenant can put a friendly, business-looking face where a real
one is missing or unsuitable.

- **An operator who declines is told what will stand in their place**, before they decide. That is the
  whole difference between a choice and a default: refusing stays free, and it is not a surprise
  afterwards.
- **The tenant may remove a real photo and replace it with a stand-in** — not only when an operator
  refuses, but when a real photograph is unsuitable for the shop's own storefront. The tenant may
  never upload a *real* photograph of somebody else. That is the line, and it is where the consent
  argument actually bites.
- **Machine replies are a tenant setting.** The tenant uploads a picture for the machine and chooses
  whether auto-replies and machine answers carry it or keep the operator's own. Neither is forced.
- **The empty case is the tenant's to fill.** No photo and no stand-in is a legitimate state.

### What this has to be honest about, and it is not the operator's side

The operator's consent story is now clean: asked, told what happens if they say no, and saying no
costs them nothing.

**The exposed party is the visitor.** A synthetic face above a real person's name tells a customer they
are looking at Pavel, and they are not. It infringes nobody's likeness and it is still a
misrepresentation — a product decision rather than a technical one. The author has taken it; this
paragraph exists so nobody later believes the question was never asked. Two things must not be decided
by omission:

- **Whether the widget says anywhere that a portrait is illustrative.** A line of small text is cheap
  and changes what the visitor was told. Not having one is also a position — take it deliberately.
- **A stand-in must never be presented as evidence.** If a transcript is exported, printed or shown
  back as a record of who said what, the face in it must not read as identifying a person.

### The machine says what it is, in words the tenant owns

Decided 2026-09-07. **The machine's name is a text field with a default of «Электронный помощник»**, and
the tenant may change it to whatever they like, on their own responsibility.

That is a better answer than a badge we design, and for a reason worth keeping: a name is read, a badge
is skimmed. *«Электронный помощник»* above a machine's reply tells a customer what they are talking to
in the same glance that a human's name would. It also removes the need to decide, on our side, how a
machine ought to look — the tenant decides, and owns the consequence of calling it something
misleading.

**This settles the machine half of the misrepresentation question and not the human half.** A stand-in
portrait above a real operator's real name still tells a visitor they are looking at that person. The
name field does nothing about that, because the name there is correct — it is the face that is not.
Whether the widget marks such a portrait as illustrative is still open, and is still the one thing this
must not decide by omission.

### Who answers for an uploaded face

The author's position, 2026-09-07: generating a stand-in is the tenant's business, and if a tenant
uploads a celebrity's photograph instead, that is the tenant's problem in court.

**As an allocation of responsibility between us and the tenant, that is ordinary and right** — it is a
warranty-and-indemnity clause, and `23-52` is already building the contract it belongs in.

**It is not immunity, and the item should not pretend otherwise.** Under `ст. 152.1 ГК РФ` the person
depicted can demand that whoever is *disseminating* their image stop, and the thing serving those bytes
to visitors is our infrastructure. A clause gives us recourse against the tenant and a defence; it does
not stop the demand arriving here. What actually protects the deployment is cheap and is not legal
text:

- **A record of who uploaded which image and when.** Without it, "the tenant did this" is an assertion
  rather than something we can show.
- **A takedown path we can execute quickly** — remove a specific image, on complaint, without a deploy
  and without touching anything else.
- **Never claiming, in our own words, that we generated it.** Marketing copy that says AGO supplies
  portraits would move the answer, and the tenant's warranty would not save it.

None of that is a lawyer's opinion, and it is not offered as one — it is the shape the build has to
support so that a lawyer's clause has something to stand on. **The clause itself goes to the lawyer
reviewing `23-52`'s contract**, not into this item.

### One thing the answers leave open, and the assumption being proceeded on

The tenant *chooses* a stand-in. **Assumption: the tenant uploads the image**, through the same
presigned path as every other file, and this product generates nothing and ships no gallery.
Generating portraits ourselves means a vendor, its terms, a cost per image and a new outbound
dependency — a separate decision, and probably a separate item. If a small built-in set was the
intent, this changes shape.

## Out of scope

- Any redesign of the widget beyond making room for the photo. `23-31`'s navigation and the widget's
  own visual language stand.
- Moderation of what an operator uploads. Worth its own thought later; a first version can rely on the
  same tenant who hired them noticing.
- Photographs of visitors. Not now, and probably not ever.

## Done when

- [ ] An operator can add and remove their own photo from the console, and declining costs them nothing.
- [ ] A visitor sees it in the widget header and beside that operator's messages.
- [ ] An operator with no photo produces a deliberate-looking widget, not a broken one.
- [ ] `personal-data.md` says what is held, where, on what basis, and how it is removed.
- [ ] Removing an operator removes the photo, proven by a test rather than by inspection.
- [x] The three questions above are answered — by the author, 2026-09-07, recorded above.
- [ ] An operator is told, before choosing, what will stand in their place if they decline.
- [ ] A tenant can place a stand-in and can never upload a real photograph of another person.
- [ ] Whether the widget marks a portrait as illustrative is decided in the change, not by omission.
- [ ] The machine's name is a tenant-editable field, defaulting to «Электронный помощник».
- [ ] An uploaded image records who uploaded it and when.
- [ ] A single image can be taken down on complaint without a deploy, shown working.
