# a visitor can introduce themselves while somebody is online

- **Stage**: 23
- **Status**: done
- **Depends on**: `23-09` — the form itself, which exists and is reused rather than rebuilt.
- **Decision**: the author's, 2026-09-07, four answers recorded below.

## What is actually true today

`23-09` built the contact form and it works. It is rendered **once**, appended to the out-of-hours
system message (`ui/widget.ts`'s `contactCaptureShown`), so it appears only when nobody is there.

**A visitor who arrives while an operator is online is never offered it.** That is most visitors during
business hours, which is most of the ones worth reaching.

## Scope

- **A modest, light-grey, link-like control reading «Представиться…»** appears **directly under the
  visitor's own first message**. Clicking it opens the existing form.
- **It stays until they introduce themselves**, and then it goes. The author's answer: under the first
  message, until done. It does not follow them down the transcript and it does not reappear.
- **One form, not two.** The out-of-hours path and this one open the same control with the same fields.
  Two entry points to one form is fine; two forms writing the same table is not.
- **The form collects a name, a phone and an e-mail, and all three are required.** The author's answer.
  Today the phone is required, the name optional and there is no e-mail at all, so this changes the
  existing control as well — which is why it is one item and not two.

## What this costs, stated because the author chose it knowingly

**Every required field lowers the share of people who finish.** Making the name and a new e-mail
mandatory trades the number of contacts for their completeness. That is a deliberate product choice and
this item implements it; it is recorded here so that if the completion rate turns out poor, the first
thing anybody reads is that the requirement was chosen rather than inherited.

The e-mail is also a new `VisitorContactDetailKind` — today the name rides as `Other`, which was a
one-item shortcut. Three fields is the point at which that stops being reasonable.

## Out of scope

- Anything the contact then *does* — the calendar carry-over is `23-59`.
- Verification. These stay unverified contacts, exactly as `23-09` left them; `14-15`/`20-09` own the
  verified path and nothing here changes it.
- Consent behaviour. `24-05`'s checkboxes render as they already do.

## Done when

- [x] A visitor writing while an operator is online sees «Представиться…» under their own first message.
      `ago-widget` `f90f1d7`.
- [x] Clicking it opens the same form the out-of-hours path opens — one control, one set of fields.
- [x] The control disappears once a contact has been left, and does not come back in that conversation.
- [x] Name, phone and e-mail are each required, and the e-mail is stored as its own kind rather than
      riding as `Other`.
      `ago-chat` `408d39b` — 62 lines of handler tests, because a required field enforced only in the widget DOM is not required. An empty name and an empty e-mail are now refused over the visitor path, and an e-mail stores as its own kind rather than riding as `Other`.
- [x] The out-of-hours entry point still works and shows the same three fields.
