# an operator turns a phone number in the transcript into a contact, in one act

- **Stage**: 23
- **Status**: ready
- **Depends on**: `23-08` — the register entry, so a new way of creating these rows does not land
  before the store is accounted for
- **Decision**: `docs/design/decisions.md` §4, the *and the operator can promote a phone out of the
  text* paragraph (2026-09-04)

## Goal

When a visitor types "call me on +7…" into the chat, the operator turns that into a contact with one
action, from the message itself, without retyping it into a form in another column.

§4: people type it into the chat because it is the easiest thing to do — the control was not where
they were looking, or it appeared at the wrong moment. Making the operator retype it is how the
number stays only in the transcript, where nobody can find it.

## Deliberately their action, never automatic extraction

§4 is explicit, and this is the whole constraint on the item: **a product that quietly mines messages
for personal data is a different product and would surprise people.** No regex over `messages.body`,
no background scan, no suggestion computed from content the system is not supposed to be reading.
The operator sees a number, decides it is one, and says so.

## What already exists, and what this actually is

The write is built: `POST /api/v1/conversations/{conversationId}/contact-details`
(`RecordVisitorContactDetailHandler`, gated on `Permission.ConversationSend`) takes a kind and a
value and creates the row; the console's visitor aside already renders a `Select` of kinds, a
free-text input and a **Record** button (`ui-inventory.md` §3.4, panel 7).

So this item is **a console affordance over an endpoint that exists** — the smallest item in the
stage, and worth its own number precisely because it is: bundled into `23-09` it would wait behind a
migration, a widget change and an ADR for no reason.

## Context to read first

- `docs/design/decisions.md` §4, the promotion paragraph and *what this dissolves*
- `docs/design/flows.md` 1.2 and 2.2; `docs/design/ui-inventory.md` §3.3 (the message rows) and §3.4
  (panel 7, the contact-details panel and its caption)
- `Ago.Chat.Application/UseCases/RecordVisitorContactDetail/RecordVisitorContactDetailHandler.cs` —
  in particular its own remarks on why it is gated on `ConversationSend` rather than a new permission
- `ago-console/src/workspace/VisitorPanel.tsx`

## Scope

- `ago-console`: an act on a message in the open conversation that pre-fills the contact-details
  panel's kind and value from what the operator selected, and puts the focus where the operator can
  confirm or correct it. **The operator confirms; nothing is written by the act of selecting.**
- The value is carried across as text the operator can edit before recording — a copied fragment is a
  guess about where the number starts and ends, and an operator correcting it is cheaper than a wrong
  row.
- The panel's caption changes with the meaning: it currently says "Recorded by an operator — never
  used to contact the visitor automatically", which stops being the whole truth once `23-09` lands.
  Coordinate the wording with that item's ADR rather than writing a second, different sentence.
- No server change. If one turns out to be needed, that is a finding worth reporting, not scope to
  absorb.

## Out of scope

- **Any automatic detection**, including a purely client-side one. §4 forbids the behaviour, not the
  implementation, and a browser-side regex over a transcript is the same behaviour.
- Promoting anything but what the operator selected — no "we also found two other numbers".
- The visitor-supplied path — `23-09`.
- Changing who may record a contact detail.

## Done when

- [ ] An operator selects a number in a message, triggers the act, and the contact panel is
      pre-filled with a kind and that value, unwritten.
- [ ] Confirming records exactly one row, with source `Operator`.
- [ ] Nothing is recorded without a confirmation — asserted on the request, not on the rendering.
- [ ] No code path reads `messages.body` looking for a pattern, in either repository — asserted by a
      test or, failing that, stated in the PR with the grep that shows it.
- [ ] The panel's caption is consistent with `23-09`'s ADR.
- [ ] `ago-console`'s ux-gate passes, including its no-untranslated-string assertion.

## Open questions

None.
