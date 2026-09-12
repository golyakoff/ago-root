# 25-62 · `VisitorContactDetailKind.Other` is actually `Name`

- **Stage**: 25
- **Status**: done — `ago-chat#263`, `ago-widget#81`, `ago-console#205`
- **Verified**: 2026-09-12 — confirmed live in `ago-widget/src/ui/widget.ts:1546-1576`: the visitor's
  own contact-capture form collects a real, dedicated name field (`result.name`) and records it with
  `Kind: "Other"` — the widget's own doc comment already says so in plain words ("records the phone,
  the name (as `Kind: "Other"`) and the e-mail"). `VisitorContactDetailKind` has exactly three members
  (`Phone`, `Email`, `Other`) — there is no fourth, dedicated `Name` member; `Other` has always meant
  "the visitor's name" at the one real call site that ever sets it. `25-58`'s own console worker
  independently caught the same mismatch and declined to label the pill "Имя" for it, on the honest
  reasoning that `Other`'s own doc comment allows a second phone number or an address too — a
  reasonable read of the code as it stood, but the live system has exactly one writer and it always
  means name.
- **Depends on**: nothing — found while investigating `25-56`'s own "visitor's name, if known" display,
  which needs a real source
- **Found**: 2026-09-12, the author's own correction after being shown the `Other` finding: "просто
  Other не нужен тогда, вместо него сделай Name, сейчас в форме виджета у него подпись Name, странно,
  что на бэк уехало Other" — the widget's own form field is already labelled "Name"; the backend enum
  member picked up the wrong word somewhere between `23-09` and `23-58`.

## What is actually true

`VisitorContactDetailKind.Other` is stored as its CLR member name (`HasConversion<string>()`), so
every existing row with a visitor-submitted name has the literal string `"Other"` in its `kind`
column today. Renaming the C# enum member alone would silently orphan every one of those rows —
`Enum.TryParse` on the API's own read path would find nothing named `"Other"` once the enum no longer
has that member, and a fresh `Name` value written going forward would never match old rows in a
`WHERE kind = ...` query without a data migration to move them.

## Scope

- **`ago-chat`**: rename `VisitorContactDetailKind.Other` → `Name`. Fix every reference this touches
  (confirmed real sites: `ConversationErrors.cs`, `VisitorContactDetailDto.cs`,
  `SetVisitorContactDetailAssessment.cs`/`Handler.cs`, `InvalidVisitorContactDetailStateException.cs`,
  `VisitorContactDetail.cs`, `VisitorContactDetailAssessment.cs` — all doc-comment references or the
  `Kind == VisitorContactDetailKind.Other` guards in `EditValue`/`SetAssessment`/
  `SetVisitorContactDetailAssessmentHandler`, which must become `.Name` and otherwise keep their exact
  behavior: a name still gets no confirm/invalid state, for the same "no channel to confirm the way a
  phone or email has" reason).
- **`ago-chat`**: a real EF migration — additive-first is not enough here, this is a data fix — that
  updates every existing `visitor_contact_details` row with `kind = 'Other'` to `kind = 'Name'`. State
  the row count affected in the Outcome, the same discipline `db-migration`'s own worked examples use.
- **`ago-widget`**: `ui/widget.ts`'s contact-capture form changes its `recordContactDetail(..., "Other", result.name)` call to `"Name"` — the wire string, not just a label.
- **`ago-console`**: `ContactDetailsPanel.tsx`'s `CONTACT_DETAIL_KINDS` tuple and every place it
  branches on the literal `"Other"` moves to `"Name"`; the `contactDetailsKindOther` i18n key (and its
  ru/en values, currently "Другое"/"Other") is renamed to something like `contactDetailsKindName`
  with real values ("Имя"/"Name") — a key named `...Other` holding the string "Имя" would be its own
  future confusion.

## Where this is likely to go wrong

- **The rename and the data migration must land together, in the same change.** A rename with no
  migration breaks every existing visitor-submitted name silently (it stops matching anything an
  `Enum.TryParse` or a `WHERE kind = 'Name'` query looks for); a migration with no rename leaves the
  C# enum still calling it `Other`, which is the exact confusion this item exists to remove.
- **`ago-widget`'s change is a wire-string change, not a cosmetic one** — if the widget still sends
  `"Other"` after `ago-chat` stops accepting it as a valid kind (once the enum member is gone), every
  new name a visitor types stops recording entirely. Both sides must ship together, or the widget
  half must land first with a compatibility window — decide and state which; given this is a portfolio
  deployment with low real traffic, landing both together and accepting a short window where an
  in-flight request could 400 is a reasonable, statable choice rather than building a compatibility
  shim for it.
- **Do not touch `Phone`/`Email` or their own confirm/invalid mechanism (`25-58`)** — this item is
  scoped to the one mislabeled member, not a broader redesign of the contact-detail kind system.

## Outcome

All three repos landed together. `VisitorContactDetailKind.Other` → `Name` in `ago-chat`
(`EditValue`/`SetAssessment`'s guards and every doc-comment reference updated, behavior unchanged — a
name still gets no confirm/invalid state). `Stage25RenameVisitorContactDetailKindOtherToName`
migrates existing rows via raw SQL (`dotnet ef migrations add` came back with an empty `Up`/`Down`
first, confirming this is a pure data fix, not a schema change) — **0 rows affected**, confirmed by
querying the local dev Postgres directly (`visitor_contact_details` is genuinely empty there).
`ago-widget`'s contact-capture form sends `"Name"` instead of `"Other"`, matching `ago-chat`'s own
`Enum.TryParse` on the read path. `ago-console`'s `contactDetailsKindOther` i18n key is renamed to
`contactDetailsKindName` with real values ("Имя"/"Name").

## Done when

- [x] `VisitorContactDetailKind` has `Phone`/`Email`/`Name` — no `Other` member remains anywhere in
      `ago-chat`'s source.
- [x] A real migration has moved every existing `kind = 'Other'` row to `kind = 'Name'` — row count
      stated in the Outcome.
- [x] `ago-widget`'s contact-capture form sends `"Name"`, not `"Other"`.
- [x] `ago-console`'s pill for this kind reads "Имя"/"Name", sourced from a correctly-named i18n key,
      not a leftover `...Other` key holding the new text.
