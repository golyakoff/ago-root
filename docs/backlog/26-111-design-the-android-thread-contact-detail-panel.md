# 26-111 · Design the Android thread's contact-detail / visitor-info panel (the "detailed conversation window")

- **Stage**: 26
- **Status**: done — design delivered (`docs/design/26-111-thread-contact-detail-panel.md` with the
  author's Q1–Q8 in §5a, plus `docs/design/26-111-contact-panel-slices.md`); sliced into implementation
  tickets `26-143`..`26-153`, which are tracked and landing under their own numbers.
- **Found**: 2026-09-25. The author asked (the day before) for an Opus design pass on the "detailed
  conversation window" and it was not filed at the time — filed now, with the author's own mockup.

## What this is

The Android thread screen (`26-15`/`26-40`/`26-41`) today shows history + composer + a title block. It
has **no contact-detail / visitor-info panel** — the bottom sheet in the author's mockup
(`docs/design/assets/26-111-thread-contact-detail-mockup.jpg`), which shows, for the open conversation:

- a header: visitor avatar + localized name, "Первый визит 14 марта · N диалог(ов)", a state chip («В работе»);
- **КОНТАКТНЫЕ ДАННЫЕ**: Телефон and Почта, masked, each with a «Показать» reveal; Имя shown as
  «Недействительно» when unverified; a one-line-per-field rule with an explanatory caption ("оператор
  ещё не подтвердил эти данные");
- tags on the conversation («Оплата», «Срочно», and a «+ метка» affordance to add one);
- «Заметки команды» (count, opens the team-notes for this conversation);
- «Прошлые диалоги» (count, opens this contact's previous conversations);
- «Приём файлов от посетителя» — a per-conversation toggle;
- actions: «Закрыть диалог» and «Ограничить» (restrict the visitor).

None of these strings exist in `ago-android` resources today; the screen is unbuilt.

## Why a design pass, not straight to implementation

Almost every element already exists on the **web console** and is backed by a real `ago-chat` (or
`Ago.Calendar.Api`) endpoint — but the mapping, the mobile interaction shape, and several product
questions need deciding before any ticket is implementable. The console references to mine:
`ago-console/src/workspace/ContactDetailsPanel.tsx`, `workspace/VisitorPanel.tsx`,
`api/contactDetailsApi.ts`, `api/visitorRestrictionsApi.ts`; and on Android the existing
`OperatorHubConnection`/`ThreadScreen` and `KtorBookingsApi`'s reveal path (`26-53` already reveals a
masked phone from the phone — reuse, don't rebuild).

## The design pass must deliver

1. **A field-by-field / action-by-action map** of the mockup to its data source: which existing
   endpoint or hub method backs each (contact details, tags, team notes, past dialogs, reveal
   phone/email, restrict visitor, per-conversation file-acceptance toggle, close conversation), and which
   have **no** backend yet (flag those as their own new items, `ago-chat`/console side).
2. **What is already built** on Android and reusable (`26-53` reveal, tags if any, the hub connection)
   vs genuinely new, so the breakdown doesn't rebuild working pieces.
3. **The mobile interaction shape**: how the panel is opened from the thread (the mockup is a bottom
   sheet), how reveal/close/restrict confirmations work on a phone, and the empty/loading/refusal states.
4. **The product questions surfaced, not silently answered** (`CLAUDE.md` rule 14 "file as the
   question"): e.g. does «Ограничить» on mobile carry the console's full restrict options or a reduced
   set; what «Приём файлов от посетителя» toggles server-side and whether that control exists; whether
   «Прошлые диалоги» opens read-only history; permission gating per element.
5. **A proposed breakdown into numbered implementation tickets** (`26-112`…), each one promise that lands
   green (`CLAUDE.md` rule 15), ordered, with dependencies — as text for the author to approve, not filed
   by the design pass itself.

## Out of scope

- Any production Kotlin, string resource, or backend change — this is design only.
- Deciding the product questions in §4 — surface them for the author.
- Filing the implementation tickets — propose them; the author approves, then they are filed.

## Done when

- [x] A design doc exists (`docs/design/` or this item, the author's call) covering §1–§4 against the
      real console/backend and the mockup. — `docs/design/26-111-thread-contact-detail-panel.md`.
- [x] A proposed, ordered list of implementation tickets (§5) is in hand for the author to approve. —
      `docs/design/26-111-contact-panel-slices.md`; approved and filed as `26-143`..`26-153`.
- [x] The product questions are written as questions, each with options and their cost. — Q1–Q8 in §5a
      of the design doc, answered by the author.
