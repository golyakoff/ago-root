# 25-21 · `/account/documents` shows what is already set as a table, not a form

- **Stage**: 25
- **Status**: ready
- **Depends on**: `23-37` built this screen; this corrects its shape once real data exists
- **Found**: 2026-09-09, the author using the screen with documents already configured

## What is actually true

`DocumentsPage.tsx` always renders an editing form, even for a document the tenant has already set.
There is no view that simply shows what is currently in effect, and no way to see who has accepted
which version — both consent documents (data-processing notice, mailing consent) version independently
per `23-37`'s own model, and each version's acceptances are a real, answerable question the UI does not
surface at all.

The intro copy — *"AGO не пишет текст — его пишете вы"* — reads as a disclaimer aimed at a form the
tenant is about to fill in; it does not belong once the screen's job is showing what already exists.

## Scope

- **When a document is already set**, show it as a card/table — the current text, its version, when it
  took effect — instead of an editable form. Editing (a new version) is a deliberate action from that
  card, not the default view.
- **A "show who accepted" action per version**, expanding into a card listing acceptances for that
  specific version — *"Принявшие Согласие на обработку персональных данных (v1, 9 сентября 2026 г. в
  11:43 Москва)"* is the shape, per the author's own example. Both document kinds (data-processing
  consent, mailing consent) get this — each its own card/table, each with its own "who accepted" list.
- **Remove `documentsPageIntro`'s "AGO не пишет текст" sentence.** It was aimed at an always-a-form
  screen; once the screen shows current state first, the sentence has nothing to attach to.
- Reuse `25-22`'s date formatting once it lands, for the "9 сентября 2026 г. в 11:43 Москва" timestamp
  shape — do not hand-roll a second formatter for this one screen.

## Where this is likely to go wrong

- **The "who accepted" list is per-version, not per-document-kind.** A tenant who published two
  versions of the same document has two separate acceptance lists, not one merged one — conflating
  them would misrepresent who agreed to which actual text.
- **This is a real data surface, not cosmetic** — check what the backend already returns for
  acceptances (likely already used somewhere for compliance/export purposes, e.g. `24-11`'s per-person
  export) before assuming a new endpoint is needed.

## Done when

- [ ] A document that is already set renders as a card/table, not a form, by default.
- [ ] "Show who accepted" expands a card listing acceptances for that specific version, for both
      document kinds.
- [ ] `documentsPageIntro`'s "AGO не пишет текст" sentence is removed.
