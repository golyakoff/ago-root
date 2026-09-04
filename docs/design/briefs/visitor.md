# Brief — visitor

A join between `flows.md` (what this person is trying to do) and `ui-inventory.md` (what exists).
**Nothing here is new judgement.** Each story is paired with the surfaces it touches, the states
those surfaces have, the states the story requires that do not exist, and the mobile constraints that
apply. Where this document says a state is missing, it is because the inventory recorded its absence
and the story requires it — not because anyone here decided it ought to be added.

Section references are to `ui-inventory.md`. Story numbers are `flows.md`'s.

---

## The role, as `flows.md` states it

**Wants**: their question answered, or a slot that suits them, with least effort and no commitment
they will regret.
**The product wants**: that they start talking at all; invest a little attention; book; and failing
that, leave a name and a phone so the conversation is not lost.

## Every surface this role can reach

The visitor never sees the console. Everything is `ago-widget`: one bundle on somebody else's page,
inside a Shadow DOM (`:host { all: initial }`), configured from the `<script>` tag plus a bootstrap
call to the server.

| Surface | Inventory | Notes |
|---|---|---|
| The launcher (closed) | §9.1 | 3.5rem circle, `💬`, tenant's accent colour, `position: fixed` 1.25rem from the bottom and the chosen side |
| The panel (open) | §9.2 | `role="dialog"`, `aria-modal="false"`, six regions |
| Message bubbles | §9.3 | five variants: visitor, operator, auto, system, pending |
| Booking content inside bubbles | §9.4 | four `contentKind`s |
| The demo host pages | §9.6 | `public-demo/index.html` (Russian) and `public-demo-2/index.html` (English), plus two local-only demo pages |

**There is no design system behind any of it.** `src/ui/styles.ts` is one template string of
hard-coded hex values; it shares no token, no type scale and no component with the console. One value
crosses the boundary: the tenant's accent colour, as `--ago-accent`.

## Mobile constraints that apply to every story below

From §11. This is the visitor's normal case — the widget lives on other people's mobile sites.

- **The widget has no viewport media queries at all.** `src/ui/styles.ts` contains exactly one
  `@media` block and it is `prefers-reduced-motion`. Every size is a fixed `rem` or a `min()` clamp,
  so the layout at 375×812 is the desktop layout shrunk by two clamps.
- At 375px the panel is `min(22rem, 100vw - 2.5rem)` = **335px wide**. It does not become a
  full-screen sheet; it floats with ~20px of the shop's page visible each side and 68px of launcher
  below it.
- Height is `min(32rem, 100vh - 8rem)` — **`vh`, not `dvh`**, unlike the console, which uses `100dvh`
  and says why. The on-screen keyboard does not change `100vh`.
- No `env(safe-area-inset-*)` anywhere; the 1.25rem bottom offset is from the raw viewport edge.
- `aria-modal="false"` while focus **is** trapped for keyboard users (`FocusTrap`) — the two
  disagree.
- The host page keeps scrolling behind the panel; the widget never locks body scroll.
- `z-index: 2147483647` is what keeps it above the shop's own fixed elements.
- Both viewports (375×812, 1280×800) are covered by the widget's own UX gate for overflow, 24px
  minimum target size and WCAG AA contrast. The overflow assertion measures the **host page**,
  deliberately.

---

## 1.1 Asking a question at all — `built`

### Surfaces

| Route/surface | Inventory | State today |
|---|---|---|
| Launcher, closed | §9.1 | one state. No unread badge, no preview bubble, no greeting prompt, no attention animation |
| Panel, open | §9.2 | header (`Chat with us`, optional booking chip, `✕`), optional demo strip, optional processing-notice strip, message log, one status line, composer |
| Composer | §9.2 | `📎` attach (a hidden native file input), auto-growing textarea capped at 6rem, **Send**. Enter sends, Shift+Enter newlines |
| Attachment feedback | §9.3 | per-bubble `.ago-status` line: `Uploading… 43%`, `Couldn't send the attachment.` |

### States it has

`Connecting…` · `Reconnecting…` · `Disconnected. Trying to reconnect…` · connected (status blank,
composer enabled) · `Chat is unavailable right now. Please try again later.` · file rejected by type
or size. Composer and attach are disabled in every state except connected.

### States this story requires that do not exist

- **The story**: *"Must want to start, which means believing the effort is small and an answer is
  coming."* **The inventory** (§9.5): *"There is no empty state. A brand-new conversation opens to an
  empty message area with a status line and a placeholder; nothing greets the visitor, names the
  shop, or suggests what to ask."* There is also no queue-position or wait-time indicator, in either
  direction.
- **The story**: *"Must not be made to … guess whether the widget is a live conversation or a contact
  form."* Nothing in §9.2 or §9.5 distinguishes the two. The panel's one status line carries
  connection state only.

### States it has that the story explicitly requires

- *"Must never happen: a widget that cannot be closed, or that captures the host page's scroll."*
  §9.2: Escape closes it, there is a `✕` in the header, and §11 records that the widget never locks
  body scroll. Both hold today.

---

## 1.2 Writing when nobody is there — `partial`

### Surfaces

| Route/surface | Who | Inventory | State today |
|---|---|---|---|
| The widget panel | visitor | §9.2, §9.3 | identical to 1.1 from the visitor's side |
| `ago-widget` auto bubble | visitor | §9.3 | `.ago-message--auto`: as the operator variant, plus a 2px left border and a small uppercase **AUTOMATIC REPLY** label drawn as CSS `content` so it never enters `textContent` |
| `/settings/auto-reply` | tenant admin (`site:configure`) | §6.4 | where the tenant writes the default reply and up to N keyword rules |

### States it has

The auto bubble is a real, distinct visual variant. The auto-reply screen has: checking permissions ·
denied · loading · load error · nine validation messages · submit error · saved.

### States this story requires that do not exist

- **The story**: *"Must not be made to care whether a reply was written by a person, and must not be
  led to believe somebody is sitting there when nobody is. Those are two different things and only
  the second is a lie."* **The author's own suggestion, verbatim**: *«не стоит разделять визуально
  автоответ робота и ответ человека, не стоит писать «оффлайн/онлайн»»*. **The inventory**: the
  `.ago-message--auto` variant does exactly the visual separation the suggestion argues against, and
  `flows.md` records that *"the widget's resting state after one is undesigned, and today looks
  identical to a live conversation"*. Both halves of that are facts about the same surface: the
  bubble is marked, the resting state is not.
- **The story**: *"Must be able to leave the question and a way to be reached."* **The inventory**:
  no contact-capture surface exists in the widget. §9.4's four `contentKind`s (`choice_list`,
  `date_time_picker`, `confirmation_card`, `form`) are the only structured-content mechanism the
  widget has, and `form` is one label, one text input and one Continue button per message.
- **The story**: *"How we know it worked … the proportion that end with a reachable contact **and**
  are actually followed up in working hours."* **The inventory**: no surface in the console shows an
  out-of-hours conversation awaiting follow-up. `/admin` (§4.1) lists every conversation with no
  filter for this and no link to open one.

### Mobile note

The out-of-hours case is disproportionately mobile and disproportionately evening. The `vh`-not-`dvh`
constraint above applies to any surface that would ask the visitor to type a phone number, because
that is the moment the keyboard opens.

---

## 1.3 Coming back to a conversation — `partial`

### Surfaces

| Route/surface | Who | Inventory | State today |
|---|---|---|---|
| The widget panel on a return visit | visitor | §9.2 | the message log renders `joinResult.history` on connect |
| The visitor-history aside panel | chat operator | §3.4 (2) | the **operator's** view of the same fact: previous conversations, state badge, `Started … — Closed …` or "Still open", a one-line ellipsised preview, opening a read-only dialog |

### States it has

Widget: connecting, connected with history, `Your previous chat has expired, so this is a new
conversation. Anything you sent before is no longer shown here.` (a `system` bubble), and
`This chat session has expired. Reload the page to start a new one.` (terminal and sticky — later
connection events cannot overwrite it).

Operator side: skeleton · danger alert · `.ago-empty` "No prior conversations with this visitor yet."
· rows.

### States this story requires that do not exist

- **The story**: *"Must be able to see their own previous messages and that the other side has
  them."* **The inventory** (§9.3): widget bubbles carry **no timestamp, no day separator, no author
  label and no read receipt**. §12.14 records this as a proven inconsistency: the console's end of
  the same conversation has all four. Nothing on the visitor's side distinguishes what was said
  yesterday from what was said a minute ago.
- **The story**: *"Must not be left wondering whether to [repeat themselves]. The uncertainty is the
  damage."* The widget has no signal that the operator has read anything (§9.3, §9.5).
- **The story**: *"Must never happen: an empty box that implies the earlier conversation is gone when
  it is not."* **The inventory**: there is no empty state at all (§9.5), so the empty box is what a
  reader sees whenever history has not yet arrived and whenever there is none. `flows.md` records the
  same: *"Whether the widget makes it discoverable is undesigned."*

---

## 1.4 Booking a slot — `partial`

### Surfaces

| Route/surface | Who | Inventory | State today |
|---|---|---|---|
| Booking chip in the panel header | visitor | §9.2, §9.4 | absent unless the embed carried `data-booking="true"`; hidden and disabled until the lazily-loaded bundle resolves; clicking it types the module's trigger phrase |
| `choice_list` bubble | visitor | §9.4 | a vertical column of full-width outlined buttons |
| `date_time_picker` bubble | visitor | §9.4, §13.14 | **rendered by the same code path as `choice_list`** — a flat column of buttons. No calendar, no month grid, no time grid |
| `confirmation_card` bubble | visitor | §9.4 | optional bold title, label/value rows, then action buttons |
| `form` bubble | visitor | §9.4 | one label, one text input, one **Continue** button. One field per message |
| `/calendar/setup`, `/calendar/workers`, `/calendar/availability` | calendar operator | §7.2, §7.3, §7.6 | what produces the slots this visitor is offered |

### States it has

Choosing an option disables every control in that message. Unknown `contentKind`s render nothing at
all — the bubble shows only its text body.

### States this story requires that do not exist

- **The story**: *"Must be able to find a time without first choosing a person, **and** find a person
  without first choosing a time — both, because customers genuinely split on this."* **The
  inventory** (§9.4): the widget has four content kinds and all four are linear — a list of buttons,
  a card, or a one-field form. There is no branching, no back step and no state that represents
  "chosen a time, not yet a person" or the reverse.
- **The story**: *"Must not be made to decide anything twice, re-enter anything."* **The inventory**:
  choosing an option disables that message's controls permanently; there is no edit or undo on a
  completed step.
- **The story**: *"the interruption is designed for — they leave the browser to read an SMS and must
  come back to exactly what they left."* **The inventory** (§11): the panel is `100vh`-based, the
  host page scrolls behind it, and there is no persisted open/closed state described in §9.5. Nothing
  in the inventory records what the panel looks like on return from an SMS app.
- **The story**: *"Must not be shown invented pressure."* Nothing in §9.4 renders a countdown or a
  scarcity claim today; the four content kinds carry only what the server sends.

### Mobile note

§11 applies in full: this is the flow the story explicitly sets *"on a phone, possibly standing up"*,
and it is the one flow that requires the visitor to type (a phone number, a verification code) inside
a `100vh`-sized panel with no safe-area inset.

---

## 1.5 Changing a booking — `planned`

### Surfaces

**None.** `flows.md`: *"What exists. Nothing. The only route today is contacting the shop."*

The inventory confirms it from the other side: nothing in `ago-widget` (§9) addresses an existing
booking, and the calendar console's own screens (§7) are operator-facing — `/calendar` is the
operator's pending-bookings queue and `/calendar/contacts` is read-only with no drill-down to a
customer's bookings (§7.7).

### Everything this story needs is absent

Listed because the story is a proposal, not a critique, and a designer needs to know nothing is being
replaced:

- no visitor-facing route to an existing booking of any kind
- no visitor identity surface — the widget knows a visitor session (§9.5), and a `Customer` in the
  calendar is identified by a verified phone
- no cancel or reschedule affordance anywhere in `ago-widget`
- no visitor-facing representation of a shop's own cancellation rules

### The one adjacent fact

§7.1: the operator's own queue has three actions — **Reject**, **Cancel**, **No-show** — that fire
immediately with no confirmation, all three the same size, weight and variant. That is the only
booking-cancellation surface that exists today, and it belongs to the operator.

---

## Cross-cutting facts from the inventory that touch every visitor story

- **§12.15** — the two deployed demo shop pages are in different languages:
  `public-demo/index.html` is Russian, `public-demo-2/index.html` is English. Their section headings
  do not correspond one-to-one.
- **§9.2** — the widget's language (English or Russian) comes from the *site's* configured widget
  locale, set by the tenant on `/settings/widget` (§6.2). The visitor has no control over it.
- **§6.2** — the tenant can set the widget's accent colour, launcher side, language, and a processing
  notice with a link. There is **no preview of the widget** on that screen; the only visual feedback
  is a colour swatch.
- **§9.2** — the demo strip and the processing-notice strip are both non-dismissible and both sit
  above the message log, so on a 335px-wide panel they consume height before the conversation starts.
