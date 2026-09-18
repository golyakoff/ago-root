# 25-140 · "Connecting…" shows under an auto-opened greeting with nothing connecting

- **Stage**: 25
- **Status**: ready
- **Found**: 2026-09-18, live, reported by the author: turning on the auto-open greeting and letting
  the panel reveal itself shows "Подключение…" ("Connecting…") under the greeting, before the visitor
  has typed anything - confusing, since nothing is actually trying to connect at that point.
- **Depends on**: none. Touches `ago-widget` only.

## The gap

`ChatWidget`'s status line (`this.status`, `ui/widget.ts:488-490`) is created with its `textContent`
hardcoded to `this.strings.connecting` at construction time - before any connection attempt has ever
been made. The only thing that ever corrects it afterward is `renderConnectionState`
(`ui/widget.ts:1269-1297`), called exclusively from real SignalR connection-state transitions inside
`connect()`.

The auto-open path (`openForAutoGreeting`, `ui/widget.ts:1028-1046`) reveals the panel - and therefore
`this.status`, sitting inside it - **by design without calling `connect()` at all**. Its own doc
comment states this plainly: "Enables the composer without a live connection" -
`autoOpenedWithoutConnecting` is what lets a visitor type and send from a panel this widget has not
connected the hub for yet, deferring the real connection to the visitor's first send
(`completeSend`, `ui/widget.ts:1595-1597`, `materializeAutoGreeting`/lazy connect-on-first-send).

Because nothing ever calls `renderConnectionState` during that window, `this.status` keeps showing its
construction-time default - "Подключение…" - for as long as the visitor has not yet sent anything,
even though no connection is being attempted and none was ever supposed to be at this point. It reads
as the widget being broken or stuck loading, directly under a greeting that otherwise looks ready to
use.

## Scope

- In `openForAutoGreeting`, clear the status line's text (`this.status.textContent = ""`) at the same
  point it enables the composer without a connection - the identical "empty until there is something
  real to report" state `renderConnectionState` already uses once a connection reaches `"connected"`.
- Do not touch `renderConnectionState` itself, and do not change the ordinary `open()` path (a
  visitor-initiated open still connects immediately and "Подключение…" is the correct, true thing to
  show for that brief real window).

## Where this is likely to go wrong

- Don't clear the status line unconditionally on every panel reveal - only the auto-open-without-
  connecting path has this problem; `open()`'s own "Подключение…" is accurate and must stay.
- Confirm the status line still updates correctly once the visitor's first send triggers the real
  `connect()` call - this item must not accidentally suppress that later, true "Подключение…"/
  "Переподключение…" reporting.

## Done when

- [ ] Auto-opening the panel (greeting shown, composer enabled, no connection yet) shows no status
      text at all under the greeting
- [ ] Sending the first message still shows "Подключение…" while the real connection is being made,
      exactly as before this item
- [ ] The ordinary visitor-initiated `open()` path is unaffected - "Подключение…" still shows
      immediately, since that path really does connect right away
