# a visitor is talking to a person and cannot see one

- **Stage**: 23
- **Status**: ready — **and it carries product questions the author should answer before it is built**
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

## The questions, and they are the author's

1. **Does the tenant's admin get to see, replace or remove an operator's photo?** There is a real
   argument for yes — it is the shop's own storefront and an unsuitable photograph is their problem
   — and a real argument for no, since it is the operator's own face and their own consent. This
   decides whether the feature is one screen or two.
2. **Is a photo shown for a bot or an auto-reply?** `14-04`'s offline auto-reply and `23-39`'s machine
   answers both write into the same transcript. Showing a human's face above a machine's words is a
   small lie that compounds; showing nothing there is inconsistent. Neither is obviously right.
3. **Does the tenant get a fallback of their own** — a shop logo where an operator has no photo —
   or is the absence always neutral? This is the difference between an empty-looking widget and a
   branded one, and it changes what the tenant expects to configure.

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
- [ ] The three questions above are answered in the change rather than settled by implication.
