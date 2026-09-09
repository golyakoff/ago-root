# 25-28 · The contact-capture phone field has no format help, and email has no real check

- **Stage**: 25
- **Status**: done — `ago-widget#75`, deployed and confirmed live
- **Depends on**: nothing
- **Found**: 2026-09-09, the author's own request

## What is actually true

`ago-widget/src/ui/contactCapture.ts`'s phone field is a bare `<input type="tel">` — no default
country, no mask, no format constraint beyond whatever a browser's own `tel` type does (nothing,
by spec). The email field is `<input type="email">`, which gets whatever loose format-checking the
browser itself applies and nothing this codebase adds on top. Neither field has any server-side
format validation either — `VisitorContactDetail` (`ago-chat`) is deliberately "an honest note, never
verified" (its own doc comment), bounded only by length. That is a considered choice for what the
value *means* once recorded, and this item does not touch it — the gap is entirely at entry time,
where a visitor typing a number gets no help getting it right.

## Scope

- **The phone field defaults to Russia, +7**, with input constrained to what a valid Russian mobile
  number actually looks like — a mask/format helper the visitor types digits into (`+7 (9XX) XXX-XX-XX`
  is the common shape), not a free-text field hoping for the best.
- **A real, checkable regex for email**, applied before allowing submit — not relying on the browser's
  own `type="email"` looseness alone. State the pattern used and why it was chosen (a well-known,
  conservative RFC-5322-ish pattern is fine; do not invent one from scratch).
- This is entry-time UX only. `VisitorContactDetail`'s own "never verified" nature is unchanged — a
  well-formatted phone number is still not proof anyone controls it, and this item does not claim
  otherwise.

## Where this is likely to go wrong

- **Bundle budget.** This is the widget's own hard-capped bundle. A full phone-formatting library
  (e.g. `libphonenumber-js`) is almost certainly too heavy for what a single-country default needs —
  this codebase's own precedent (`23-62`'s ADR-0162: hand-rolled ZIP writer over `jszip`/`fflate` on
  bundle-cost grounds, not principle) is to hand-roll a small, focused formatter rather than pull in a
  general-purpose library, unless a real gzipped-size measurement says otherwise. Measure before
  deciding, and say what was measured.
- **A visitor who is not in Russia still needs to be able to type a number.** "Defaults to Russia, +7"
  should not become "cannot enter anything else" — decide and state how a non-Russian number is
  handled (an escape hatch, a country-code prefix the visitor can edit, or similar), rather than
  silently locking the field to one country's shape.
- **Do not add server-side format rejection as a side effect.** `VisitorContactDetail`'s own design is
  to accept what an operator or visitor wrote down, unverified — tightening the client's own input
  experience is this item's job; making the server start rejecting values it previously accepted is a
  different, larger change this item does not authorize.

## Done when

- [x] The phone field defaults to +7 (Russia) and constrains/guides input to a valid Russian mobile
      shape, with a stated (not silent) way to enter a non-Russian number — a leading `+` followed by
      a different country code is left as digits only, never forced into the Russian shape.
- [x] Email is checked against a real, named regex before submit is allowed (the WHATWG `type=email`
      reference pattern), not just the browser's own `type="email"` behavior.
- [x] The widget's gzipped bundle size is measured before and after: 32.3 KB → 33.3 KB, +1.0 KB against
      the 45 KB budget (no dependency added — hand-rolled per ADR-0162's own precedent).
