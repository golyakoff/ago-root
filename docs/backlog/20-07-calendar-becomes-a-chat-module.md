# AGO Calendar becomes a chat module, behind the contract rather than beside it

- **Stage**: 20 (and 14 — the contract is Chat's, the first implementation is Calendar's)
- **Status**: blocked on `20-06`
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

## Scope

- **The primitive set**, derived from `20-06`'s flow: a choice list, a form, a confirmation card, a
  date-and-time picker — whichever of these the real flow needs, and nothing it does not.
- **A text rendering for every primitive**, because that is what makes SMS and Telegram work at all.
  A primitive without one is not finished.
- **The transport decision**, with an ADR, and the step latency measured on the chosen shape.
- **`20-06`'s booking widget moved behind the contract**, so that the same flow runs in a chat
  conversation without Calendar shipping code into the widget bundle.
- **The third guard from `adr/0065`**: a check for string literals of known module keys inside
  `Ago.Chat.*`. The IL scan cannot see it, and it is the cheapest way to shortcut the whole design.
- **The registry**: one row saying site X has module K enabled, and the entry point rendered from it.

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

## Open questions

- **What a module may observe in a conversation before the visitor enters a task.** `adr/0065` names
  this as a personal-data decision (`personal-data.md`) rather than an implementation detail. It may
  well need deciding here, because "propose yourself when relevant" is the first thing anyone will ask
  for after this ships.
- **What happens to a half-finished task when an operator intervenes.** The principle is decided —
  the operator may always intervene, and the escape cannot be suppressed. Whether the task stays open,
  and who may resume it, is not.
