# AGO Calendar becomes a chat module, behind the contract rather than beside it

- **Stage**: 20 (and 14 — the contract is Chat's, the first implementation is Calendar's)
- **Status**: ready — `20-06` merged
- **Depends on**: `20-06` — the console and booking widget. Deliberately built *outside* this seam, so
  that the seam is designed against a flow that exists.
- **Decides**: two of the questions `adr/0065` explicitly left open.

## Goal

A visitor books an appointment **inside a conversation**, on any channel, and `Ago.Chat.*` contains no
knowledge that appointments exist.

## Why this is a separate item, and why it comes after `20-06`

`adr/0065` fixed the *shape*: Chat handles `moduleKey`, `task` and `step`, never opens a payload, owns
a closed vocabulary of primitives that modules fill in. It deliberately did **not** fix two things,
because fixing them without a real booking flow in hand is the premature generalisation this project
keeps naming:

- **Which primitives the closed vocabulary actually contains.** `20-06` produces the first real
  answer-by-answer flow. The set is derived from it, not guessed ahead of it.
- **Transport: in-process or over the wire.** The leaning recorded in `adr/0065` is the wire — most
  steps run at human pace, and an unreachable module degrades honestly into the escape to an operator
  that the contract already requires. A package reference would give compile-time checking at the cost
  of a product-to-product dependency for which `adr/0012` sets no precedent. **This item decides it and
  records why**, with the hop measured rather than assumed.

## Relation to `21-01`, which was written first

`21-01` (unattended booking through a channel) is blocked on two questions. **`adr/0065` answers the
second of them** — "who parses the intent, without one product depending on the other's domain" — by
deciding that in v1 nobody does: a module being enabled means its entry point is present, and
recognising "I'd like to book" is domain knowledge by another name. The first, "what carries the
structure", was answered by `14-06`/`adr/0061`.

The two items are not the same work and the split is the channel:

- **This item needs no new channel.** The widget alone proves the seam, and the text rendering proves
  the vocabulary is not widget-shaped. It can start the moment `20-06` merges.
- **`21-01` needs a real inbound channel** (`14-02`/`14-03`/`14-05`) and stays in Stage 21. What it
  inherits from here is a step model and a settled answer to its second blocker, so its remaining
  scope is genuinely the channel side and the tenant toggle.

`21-01` should be re-read against `adr/0065` when it is picked up; its three candidate UX directions
were written before the closed primitive vocabulary existed, and at least one of them (free-text
understanding) is now out of scope by decision rather than by preference.

## Decided in planning, 2026-08-29 — read before touching Scope below

Four questions this item's own Scope left for the implementer were argued through and settled ahead of
time, deliberately, because each one is easy to get wrong in a way that is invisible until a second
module exists. The reasoning is recorded here in full rather than left as a bare conclusion, so a
worker doesn't have to reconstruct *why* — matching this item's own "decide it here rather than letting
a future test failure decide it" standard, applied a level earlier.

**Transport: over the wire, confirmed — not reopened, just settled.** `adr/0065`'s own leaning is
correct and this item does not second-guess it: most steps run at human pace, and a package reference
would create the exact product-to-product code dependency `adr/0012` gives no precedent for. The ADR
this item still owes (see Scope below) records this with the measured hop latency — the decision itself
needed no further argument once framed this way twice (here, and originally in `adr/0065`).

**Booking code comes out of the base widget bundle — the guard is not restated.** Of the two options
the Scope bullet below named, this item picks the second: move `ago-widget/src/booking/` out of the
base bundle entirely, into a module-owned bundle loaded only when Calendar is enabled for a site. The
alternative — redefine `adr/0065`'s guard as "no inputs from *another product's* directory" instead of
"no inputs from *any* module directory" — was rejected because it only widens the loophole the guard
exists to close: the guard's whole point is that the base bundle stays product-agnostic, and carving
out an exception for the one module that currently exists is exactly the kind of premature accommodation
that stops meaning anything once a second module needs the same carve-out. 2.7 KB gzipped is a small
enough cost that removing it costs little and keeps the guard's original, stricter wording intact.

**How a visitor enters a task: an explicit, typed command, never inferred from free text.** The visitor
types a message starting with `/` followed by one of the module's own registered trigger words (e.g.
`/booking`, `/запись`) — structurally identical to a button click, not a step toward the intent
detection `adr/0065` already ruled out, because it is an exact, deterministic string match against a
known, finite, per-site vocabulary, never a guess at meaning. A widget-rendered chip that inserts and
sends the identical trigger text is optional UI sugar over the same one signal, not a second code path —
mirroring how Telegram's own bot command buttons work, and reusing (as a UX convention, not shared code,
since it's a different app) the exact "`/` as the first character opens a picker" interaction `18-03`
already shipped for the operator console's canned responses. This gets channel-agnosticism for the
*invocation* side for free: a typed `/booking` means the same thing on SMS, Telegram, and the widget,
with no per-channel special-casing.

**Trigger words are a configured array, owned by the module, opaque to Chat.** Not a single guessed
word: an array, because the right word might need a synonym or a full replacement later, and because it
must work in more than one language at once (`/booking` and `/запись` both resolve to the same module,
simultaneously — no visitor-locale detection needed, which is a simplification, not a gap). The array is
static configuration on Calendar's own deployment config (matching this item's own already-decided "Calendar
is wired statically, not a discovered plugin" stance — the same category as `Auth:Keycloak:Authority`,
changed by editing config and redeploying, not by a tenant-facing admin screen nobody asked for this
item to build). Chat's module registry (see the Scope bullet below) stores this array per registered
module as an opaque list of strings — it is compared for an exact, case-insensitive match, never
interpreted, the same "the vocabulary is opaque to Chat" discipline `moduleKey`/`task`/`step` already
established. **A cheap guard worth adding while it's free**: registering two enabled modules on the same
site with an overlapping trigger word should be rejected at registration time, not resolved by
first-match-wins at runtime.

**Every choice-shaped primitive's answer is a picked option's id or number — never free text — on
every channel, including the widget.** This is the piece that makes "one canonical text rendering per
primitive kind" (already in Scope below) actually sufficient rather than merely convenient: if a
`choice_list` primitive could be answered with an open sentence ("I'll take the later one"), a text
channel would need exactly the free-text understanding this whole design exists to avoid, just moved
from invocation to reply. Framing the reply as "reply with the option's number" removes that
possibility structurally rather than by discipline — a widget click and an SMS reply both resolve to
the identical wire fact ("visitor selected option `X`"), so no per-channel reply-parsing logic is
needed and none should be written. The text rendering itself is defined **once per primitive kind**, by
`Ago.Chat.*` (since it owns the closed vocabulary), and reused by every text channel and every module —
Calendar supplies the primitive's data (option labels, a date grid's cells), never its own bespoke
formatting. Telegram is a partial exception worth naming rather than flattening: its Bot API supports
native inline buttons, a real third rendering tier between the widget's full UI and SMS's bare numbered
text — investigate that as part of `14-07`'s own channel work when this item's text rendering reaches
Telegram, not as a reason to complicate the primitive contract itself now.

## Scope

- **The primitive set**, derived from `20-06`'s flow: a choice list, a form, a confirmation card, a
  date-and-time picker — whichever of these the real flow needs, and nothing it does not. Every
  choice-shaped primitive's reply is a picked option's id/number, never free text — see the planning
  section above.
- **A text rendering for every primitive**, defined once per primitive kind by `Ago.Chat.*` and reused
  by every module and every text channel — because that is what makes SMS and Telegram work at all. A
  primitive without one is not finished.
- **Explicit task invocation**: a visitor-typed `/`-prefixed command matched against the site's enabled
  module registry (see the planning section above) — deterministic string match, not intent detection.
  An optional widget chip that inserts and sends the identical text is UI sugar over the same signal,
  not a second path.
- **The transport decision**, with an ADR, and the step latency measured on the chosen shape — over the
  wire, per the planning section above; the ADR records why with the real number, not a re-litigation.
- **`20-06`'s booking widget moved behind the contract**, so that the same flow runs in a chat
  conversation without Calendar shipping code into the widget bundle — `ago-widget/src/booking/` moves
  out of the base bundle entirely (the planning section above settles this in favour of moving the code,
  not restating the guard).
- **The third guard from `adr/0065`**: a check for string literals of known module keys inside
  `Ago.Chat.*`. The IL scan cannot see it, and it is the cheapest way to shortcut the whole design.
- **The registry**: one row saying site X has module K enabled, the entry point rendered from it, and
  an opaque array of the module's own registered trigger words for the invocation command above.
  Registering two enabled modules on one site with an overlapping trigger is rejected at registration
  time.

## Out of scope

- **Intent detection.** `adr/0065` decided v1 has none: module enabled means the entry point is
  present. Recognising "I'd like to book" is domain knowledge by another name.
- **A module runtime** — discovery, sandboxing, versioning, third-party publication. Calendar is the
  only implementation and is wired statically.
- **Open kinds and per-product renderers.** Deferred by `adr/0065` until the closed vocabulary meets a
  concrete need. If this item finds one, it records the need and does not open the door on the spot.
- **Who confirms a chat-originated booking** — `20-08`, because it is an authorisation question
  touching `adr/0027`, not a contract-shape question.

## Done when

- [ ] A visitor completes a booking end to end inside a conversation, in the widget.
- [ ] The same flow completes over a text-only channel using the primitives' text renderings, proving
      the vocabulary is not secretly widget-shaped.
- [ ] `Ago.Chat.*` contains no type reference to `Ago.Calendar.*` **and no string literal of a module
      key** — both proven by a test that fails when either is added.
- [ ] The base widget bundle has zero inputs from module directories, checked the way `8-11` checked
      the demo bundle.
- [ ] A module that is unreachable degrades to the escape to an operator, and the visitor is told —
      proven by a test, not by inspection.
- [ ] An ADR records the transport decision with the measured step latency.
- [ ] A visitor-typed trigger command starts the task on every channel the flow is proven on, matched
      against the registry's opaque trigger array — and two modules registering the same trigger on one
      site is rejected, proven by a test.
- [ ] Every choice-shaped primitive is answered by option id/number on every channel, including the
      widget — proven by the same reply path handling a widget click and a text reply identically.

## Open questions

- **What a module may observe in a conversation before the visitor enters a task.** `adr/0065` names
  this as a personal-data decision (`personal-data.md`) rather than an implementation detail. It may
  well need deciding here, because "propose yourself when relevant" is the first thing anyone will ask
  for after this ships.
- **What happens to a half-finished task when an operator intervenes.** The principle is decided —
  the operator may always intervene, and the escape cannot be suppressed. Whether the task stays open,
  and who may resume it, is not.
