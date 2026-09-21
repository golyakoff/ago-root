# 26-01 · Design push notification delivery for the Android app

- **Stage**: 26
- **Status**: ready
- **Found**: 2026-09-21, the author, reviewing `26-00`'s own mockups: "это самое ужасное, что
  может быть... я делаю телефонное приложение именно потому что надеялся на нём использовать
  возможности уведомлений... САМАЯ ВАЖНАЯ ФУНКЦИЯ приложения - телефон может быть убранным в
  кармане и получив сообщение, завибрировать и привлечь внимание оператора." (this is the whole
  reason the app exists; the author is explicit that this is worth rewriting the entire
  `Ago.Chat.*` backend if that is what it takes - there are zero real tenants on the live
  deployment today, so this stage may change anything freely).

## What this item is, and what it deliberately is not

**A design/planning item, not an implementation one** - the same two-phase discipline `26-00`
itself already applies to the whole app. `26-00`'s own `plan.md` already named the gap ("no push
infrastructure anywhere in the product... real push is a backend change in `ago-chat`, not
Kotlin") as a caveat; this item is where that caveat gets an actual, buildable design, produced by
someone who has read the real code rather than assumed its shape. Implementation is a later item
(or several), numbered once this plan says what they are.

## What is actually true today (confirm live, do not assume)

The console's own alerting (`18-05`, `ago-console/src/workspace/alerts.ts` +
`useAlerts.ts`) is the browser's `Notification` API, requires the tab open and the SignalR
connection live, and produces nothing once the page is backgrounded or closed - confirmed by
reading that code, not inferred. There is no Firebase Cloud Messaging integration, no device-token
storage, no APNs, anywhere in `Ago.Chat.*` - confirm this is still true (a fresh `grep`, not last
week's memory) before designing around it.

## Scope

- **Read the real notification-worthy events first.** What in `Ago.Chat.*` today already knows
  "an operator needs to know about this right now" - a new assignment, a waiting-queue entry, a
  visitor message on an assigned conversation, a pending booking nearing its confirm-by deadline?
  `alerts.ts`'s own rules are the client-side half of this; find the server-side event(s) that
  already carry the same information (the outbox's own integration events are the likely source -
  non-negotiable rule 4 already requires every state change to publish one) rather than inventing
  a second signal.
- **Design device registration**: an endpoint (or a message) that associates a device's FCM
  token with an operator and a site, survives token rotation (FCM tokens are not stable long-term
  - design for a genuine refresh flow, not an assumption that a token lasts forever), and is
  revoked on sign-out. State where this lives architecturally (a new `Ago.Chat.*` aggregate, a
  read-model table, whatever the actual data shape calls for) and why, per this project's own
  Clean Architecture rules (`docs/architecture/clean-architecture.md`) - a port in Application, an
  adapter in Infrastructure, no framework leaking into Domain.
- **Design the fan-out mechanism**: an outbox consumer that turns "operator needs to know" events
  into FCM sends, reusing whatever decision logic `alerts.ts` already encodes (who gets alerted,
  for what, and - importantly - respecting the *already-existing* multi-connection-per-operator
  presence model `ui/widget.ts`'s own remarks and `25-203`'s own investigation both touched on for
  the widget side; the equivalent question here is "does a push fire if the operator already has a
  live, foregrounded desktop console open" - decide and state the rule, do not leave it implicit).
- **State the real cost** of each design choice - this project does not invent effort numbers, but
  it does state real structural costs: which existing hosts change (`Ago.Chat.Api`? A new consumer
  in `Ago.Chat.Worker`? A new host entirely?), what new infrastructure is needed (an FCM service
  account credential - where does it live, per `docs/architecture/secrets.md`), and what happens on
  quiet failure (FCM is unreachable, or a token is stale) - never a silent drop with nobody able to
  tell.
- **Note explicitly what this item does not need to answer**: the iOS/APNs side of this is real
  future work (the author's own stated plan for a native iOS app after Android), but is not this
  item's job to design in full - name where the design already generalizes (an abstraction over
  "push provider" at the port level, if that falls out naturally) and where it deliberately does
  not (do not build an unused APNs adapter now; that is exactly the "second consumer" premature
  generalisation `adr/0178` already reasoned about for a different layer).
- **Write the ADR if the analysis reaches a real architectural decision** (a new port, a new
  aggregate, a materially different outbox-consumer shape) - this is exactly the kind of decision
  `docs/adr/` exists for. Confirm the next free number before using it (do not reuse `0178`).

## Out of scope

- Actual implementation - this item produces a plan/design (and an ADR if warranted), not working
  code.
- The Android client's own notification-channel UI (`26-00`'s own `docs/architecture.md` already
  named this screen; it depends on this item's own device-registration design, not the reverse).
- The iOS/APNs implementation itself.

## Done when

- [ ] The real, current notification-worthy events and their existing server-side signal (or the
      absence of one) are confirmed against the actual code, not assumed.
- [ ] Device registration is designed - the data shape, the token-refresh story, revocation on
      sign-out - and placed correctly in the layering (port/adapter, which host).
- [ ] The fan-out mechanism is designed, including the "operator already has a live desktop
      console open" question, answered explicitly rather than left implicit.
- [ ] Real structural costs are named for each major choice - which hosts change, what new secret
      material is needed and where it lives, what a delivery failure looks like and how it is
      noticed.
- [ ] The iOS/APNs boundary is named explicitly - what generalizes for free, what is deliberately
      not built yet, and why.
- [ ] An ADR exists if the analysis reached a real decision, using a freshly-confirmed free number.
