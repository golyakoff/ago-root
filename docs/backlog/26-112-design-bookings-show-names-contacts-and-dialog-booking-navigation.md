# 26-112 · Design the Записи list to show real names + contacts, and link a booking to its dialog both ways

- **Stage**: 26
- **Status**: ready — a design/scoping pass (no production code) that also updates the mockup. Deliverable
  is a refined mockup + a spec + a proposed breakdown into implementation tickets for the author to
  approve. This is the "make it convenient" brief: the current bookings list is not acceptable and the
  target is not fully in any existing mockup yet.
- **Found**: 2026-09-25, by the author, using the shipped Записи screen on a real phone.

## What the author is unhappy with (verbatim intent)

- **Booking creation now REQUIRES contact data** — a booking cannot be made without it, and the required
  set includes a **name** and a **phone**. So every booking has a real name and phone behind it.
- **The Записи list shows no names**, which is wrong — the name matters most, and it is the first thing an
  operator needs to recognise a booking. Today rows lean on the emoji-pair visitor handle
  («Сова · Клубника») and a raw hex visitor code (`7c4e18f0`) instead of the person's actual name.
- **There is no way to see the contact from a booking** — the phone is mandatory, so it must be
  reachable from the list somehow; the design for that does not exist yet.
- **A booking and its dialog must be linked both ways**: from a booking created inside a conversation,
  jump to that booking on Записи → Утверждены; and from a confirmed booking, jump back to the dialog it
  came from.
- Do NOT accept "the API doesn't have it, so we won't do it." Where the data or the link isn't in the
  API yet, propose the API change that makes the convenient design possible (`26-111`'s same principle).
  Convenience first; the mockup is the target, we build it.

## The author's mockup to refine (described; the author will confirm the image)

Записи → «Утверждены» selected. Segmented tabs «Ожидают (2) | Утверждены | Клиенты». A horizontal day
strip (ПН 21 … СБ 26, one day selected, dots under days that have bookings). Below, bookings **grouped by
master/staff** with a section header per master and a count («ИРИНА СОКОЛОВА · 4 записи», «ПЁТР КИМ · 1
запись»). Each booking row: start time (10:00), service name (Стрижка), and a **client line** — in the
mockup this is boxed in red to mark the slot that must become the real name: today it renders the
emoji-pair handle and a hex code and duration («Сова · Клубника · 7c4e18f0 · 60 мин»; another row shows
«Анна К. · 45 мин»). Bottom nav Диалоги (3) / Записи (2) / Команда / Аналитика / Ещё.

**Refinement the author asked for:** figure out how to display the real **name** in that client slot
(the red-boxed area); emoji icons need not be drawn in the mockup; keep the master-grouped, day-selected
shape. The updated mockup is a deliverable of this pass.

## The design pass must deliver

1. **Reconcile the mockup against the real API** (`Ago.Calendar.Api` `/api/v1/console/confirmed-bookings`
   and the pending/queue/contacts endpoints; the console's `CalendarBookingsPage.tsx` /
   `CalendarContactsPage.tsx` and their API modules; the Android `ConfirmedBookingsScreen.kt` /
   `BookingsScreen.kt` / `KtorBookingsApi.kt`). For the **name** and **phone** specifically: does the
   confirmed-booking payload already carry the contact's name and phone, or only the visitor handle/code?
   If not, that is a **GAP** → propose the API change (which endpoint/DTO/field) to include the booking's
   real contact name and a reveal path for the phone, since contact data is mandatory at creation.
2. **How to show the name** in the row (the red-boxed slot) — what to show when a name is present vs the
   fallback, how it coexists with the emoji-pair identity the rest of the app uses, and how the visitor
   hex code stops being the thing an operator reads.
3. **How to view the contact / phone from a booking** — the interaction (row tap? a detail sheet? reuse
   `26-53`'s reveal and `26-111`'s contact-detail panel?), consistent with `26-111`'s in-dialog contact
   panel so the two do not diverge. Call out the overlap with `26-111` and keep them coherent.
4. **The two-way dialog ⇄ booking link** — the data that ties a booking to the conversation it was created
   in (does it exist in the model/API today? if not, propose it), and the navigation both directions
   (from the in-dialog booking chip/step to Записи→Утверждены at that booking; from a confirmed booking
   to the originating dialog/thread).
5. **Product questions surfaced as questions** (`CLAUDE.md` rule 14), each with options and cost — not
   decided. (E.g. what identity to show when the chat handle and the booking contact-name differ; whether
   the phone is shown inline or behind a reveal on this list; what to do for a booking with no linked
   dialog, if that is possible.)
6. **The refined mockup** (an updated visual — the author asked for the mockup itself to be updated) and
   **a proposed, ordered breakdown into implementation tickets** (`26-11x`…), each one promise that lands
   green (rule 15), including any API-change tickets from §1/§4 — as text for the author to approve; do
   not file them, do not edit docs/roadmap.md or docs/adr/README.md.

## Out of scope

- Production code, string resources, backend changes — design only.
- Deciding §5's questions — surface them.

## Done when

- [ ] A design doc covers §1–§4 against the real API + the mockup, with every GAP paired to a concrete
      proposed API change (never a "skip it").
- [ ] An updated mockup exists (names displayed; contact/phone reachable; the master-grouped/day shape kept).
- [ ] A proposed, ordered implementation-ticket breakdown + the product questions are in hand for the author.
