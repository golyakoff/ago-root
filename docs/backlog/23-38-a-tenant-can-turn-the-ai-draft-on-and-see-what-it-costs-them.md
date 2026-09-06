# a tenant can turn the AI draft on for themselves, and see what it sends

- **Stage**: 23
- **Status**: ready
- **Depends on**: `25-04` — hard. Until the add-on exists there is nothing for this screen to switch.
- **Decision**: `adr/0078` chose the AI kinds; `25-04` decides how it is bought and consented to

## Goal

A tenant who has bought the AI add-on can turn the reply draft on, off, and read what it sends before
deciding.

## What is actually true today, verified 2026-09-06

**The feature exists and has no screen.** `19-01` built `YandexGptReplyDraftClient`; `ChatModule`
registers the real client when an API key and folder id are present and an `Unconfigured*` one
otherwise. **No key is set in any overlay**, so nothing reaches the vendor.

But the switch is AGO's, deployment-wide — the finding `24-08` recorded and `25-04` fixes. `25-04`
makes the add-on buyable and off by default; **this item is the surface a tenant actually touches.**

## Why a screen rather than "it is on when you buy it"

Because what it sends is not obvious and a tenant is entitled to know before switching. The draft
sends **the conversation's own message history** as prompt context — not a summary, not the last
line — and that is the fact `25-04`'s agreement asks them to accept. An agreement accepted at purchase
and a switch flipped months later are different moments; the screen is where the second one happens
and where the first one is repeated in plain words.

## Scope

- On and off, per site, for the reply draft specifically.
- **What it sends, said on the screen**, not only in the agreement: the conversation's message text,
  to a named vendor, and nothing else — no contact details, no attachments, no other tenant's data.
- Refused with a clear reason when the add-on is not bought, rather than absent — this is exactly what
  `23-31`'s muting rule is for: a tenant can obtain it themselves.
- Off is the state a tenant lands in, always.

## Out of scope

- Buying the add-on and accepting its terms — `25-04`.
- Changing what the draft does or how it prompts.
- The categorisation feature's own screen, if it needs one. It runs in the background over closed
  conversations and a tenant may never want to think about it; whether it needs a switch of its own is
  a separate question this item does not answer.

## Done when

- [ ] A tenant with the add-on can turn the draft on and off, and it is off until they do.
- [ ] The screen says what leaves the deployment, in the tenant's own language.
- [ ] Without the add-on the screen explains that rather than disappearing.
