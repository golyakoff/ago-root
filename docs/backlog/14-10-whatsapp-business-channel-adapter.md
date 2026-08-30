# AGO Inbox: WhatsApp Business channel adapter

- **Stage**: 14
- **Status**: built (2026-08-30, `ago-chat` branch `feat/14-10-whatsapp-channel-adapter`, not yet
  merged) — a real message reaches an operator and a real console reply reaches WhatsApp back, both
  proven against a real Postgres and the real production handler/endpoint chain (`WhatsAppWebhookEndpointsTests`);
  **not yet verified against a real WhatsApp Business number and a real Meta App** — no such account
  exists in the environment this item was built in. See "What was and wasn't verified" below before
  checking the remaining Done-when boxes.
- **Depends on**: `14-01-external-channel-identity-and-inbound-port.md` — reuses the port and
  `ChannelIdentity` concept unchanged, the same way `14-02` (MAX), `14-07` (Telegram) and `14-08` (VK)
  already do

## Goal

A visitor messages a shop's AGO Chat operators through WhatsApp, and gets a real operator reply back
through the same channel — the fourth concrete external channel adapter.

## Why this, and why now

`ago-business/docs/decisions/0009` names WhatsApp as Level 1 (basic trust as a chat tool) — the single
channel it calls out by name as the one the nearest direct competitor has and AGO does not, for the target customer (`0002`: a
small Russian online shop) specifically. `ago-business/docs/decisions/0010` removes the one thing that
was blocking it: `14-05`'s own WhatsApp legal-review box, still genuinely unfinished, is no longer a
prerequisite for starting the engineering work — the author accepted that risk explicitly, in `0010`,
not silently here. **Read `14-05`'s own file before assuming "legal is fine now" — it is not; the
decision is to build anyway, and that decision belongs to `0010`, not to this item pretending the
question was answered.**

## Context to read first

`14-08`'s own backlog file ("Confirmed against VK's own documentation" section) — the template this
item's own investigation should follow: find WhatsApp's actual current API shape from Meta's own
published documentation (or the most authoritative source reachable from this environment), not from a
third party's summary, and say plainly which source was actually used if the official one is
unreachable. `14-02`'s "Tenant routing and credential ownership" section — the same question needs
answering again for WhatsApp's own credential shape, which is real API-provider-specific detail, not
assumed to be identical to MAX/Telegram/VK's own answer. `docs/architecture/resilience.md`'s
outbound-webhook treatment, reused unchanged through `14-01`'s port, exactly as every other adapter
already does.

## What is already known, stated so this item does not have to re-derive it

WhatsApp's Business Platform (Meta's own Cloud API, the one `14-05`'s legal-review section names) is
webhook-based for inbound messages, similar in shape to VK's Callback API — verify the exact
confirmation handshake and payload shape from Meta's own current documentation rather than assuming
VK's shape transfers, the same caution `14-08`'s own file gives about MAX's shape not transferring to
VK unchanged. Meta's own API generally requires message **templates**, pre-approved by Meta, for any
message sent outside a 24-hour customer-service window opened by the visitor's own inbound message —
this is a real constraint on the *outbound* side this item's adapter has to respect (a reply inside the
24-hour window is free-form; a reply after it must be a template), unlike every channel this project
has built so far, none of which had a time-boxed free-form window. State whether the target customer's
own use case (answering a visitor who just messaged) ever needs to send outside that window before
building template support — it may not, and building unused template machinery would be exactly the
premature generalization `CLAUDE.md` warns against.

## Confirmed against Meta's own documentation, 2026-08-30

`developers.facebook.com` was directly reachable from this environment — unlike `14-02`'s MAX and
`14-08`'s VK, both of which had to fall back to a third-party write-up or an official SDK's source
because their own primary documentation host was unreachable, this item's source of truth is Meta's own
current Cloud API reference pages, fetched live. This is firmer ground than either precedent had.

- **Base URL `https://graph.facebook.com`, versioned with a `/{version}` path segment (`v26.0`, the
  current stable version at build time — Meta releases a new one every few months, so a future reader
  should re-check rather than trust this indefinitely), the access token travels as an
  `Authorization: Bearer` header.** A fourth genuinely distinct shape: MAX puts the token in a header
  with no version segment, Telegram puts it in the URL path itself, VK puts it in an ordinary POST
  parameter.
- **Outbound send is `POST /{phone-number-id}/messages`**, a JSON body
  (`messaging_product`/`recipient_type`/`to`/`type`/`text.body`), answered with a real non-200 HTTP
  status on failure *and* the terminal/transient distinction living in the JSON body's own numeric
  `error.code` regardless of status — the union of MAX's own "status code carries the outcome" shape and
  VK's own "body carries the outcome, status is always 200" shape, not a repeat of either
  (`WhatsAppApiClient`'s own remarks have the full reasoning and the confirmed code table).
- **The 24-hour customer-service-window constraint is real and numbered**: error `131047` ("more than 24
  hours have passed since the recipient last replied") is what Meta returns for a free-form message sent
  outside the window, confirmed from Meta's own error-codes reference — not merely named in prose the
  way this item's own backlog note first described it. **Decided: template-message support is out of
  scope for this item.** AGO Chat's own target use case — an operator answering a visitor who just
  messaged, through the same console queue every other channel already uses — is squarely inside the
  window on every ordinary path: the window opens the instant the visitor's own message is recorded, and
  an operator's reply follows within the same conversation, not after a day of silence. Building
  template support would mean a Meta-approval workflow this system does not control, a template-selection
  UI no other channel needs, and variable-substitution machinery for a case the product's own use case
  does not reach — the premature generalization this item's own "What is already known" section warned
  against. What is built instead: a `131047` refusal surfaces as an ordinary, tenant-visible
  `ChannelSendOutcome.Refused` naming the real constraint, proven end to end through the real adapter
  (`WhatsAppChannelAdapterTests.SendAsync_WhenWhatsAppRefusesOutsideThe24HourWindow_ReturnsRefused`) —
  the constraint is respected, not ignored; only the workaround machinery is left unbuilt.
- **The webhook is App-wide, not per-tenant — the one shape difference from every precedent, and the
  central finding of this item's own research.** Confirmed from Meta's own Embedded Signup ("tech
  provider") documentation: "all webhooks for all of your onboarded business customers will be sent to
  your app's callback URL." Every WhatsApp Business Account a shop connects through AGO's own Meta App
  delivers to the identical single URL, authenticated by the identical App-wide secret — there is no
  per-credential webhook secret the way MAX's `POST /subscriptions` or VK's Callback API settings page
  each hand back. See "Tenant routing and credential ownership" below for the full consequence.
- **Inbound webhook signing is Meta's own generic Graph API mechanism, not WhatsApp-specific**: every
  POST delivery carries `X-Hub-Signature-256: sha256={hex HMAC-SHA256 digest}`, keyed by the Meta App's
  own App Secret over the raw request body — confirmed from Meta's own Graph API webhooks documentation,
  the mirror of `6-03`'s outbound `X-Ago-Signature` scheme, computed against one App-wide key rather than
  a per-credential value.
- **The one-time (and repeatable, on-demand) verification handshake is a `GET` with three query
  parameters** — `hub.mode=subscribe`, `hub.verify_token`, `hub.challenge` — answered by echoing
  `hub.challenge` back as the entire plain-text response body if `hub.verify_token` matches a value AGO
  itself chose and pasted into the Meta App Dashboard once. Shaped differently from VK's own live
  `groups.getCallbackConfirmationCode` API call (a static preshared value compared on a `GET`, not a live
  call), proven end to end through the real route (`WhatsAppWebhookEndpointsTests`).
- **The inbound envelope is natively a batch container** (`entry[]`, each with its own `changes[]`, each
  potentially carrying several `messages[]`) — unlike MAX's/VK's own natively single-event wire shapes.
  `WhatsAppInboundMessageParser.Parse` returns a list and walks every level, proven against a real
  two-message batch through the real route (`WhatsAppWebhookEndpointsTests.Delivery_WithTwoMessagesInOneBatch_...`) —
  a parser that only read the first message would silently drop the rest the one time Meta actually
  batches two together.
- **A status-only delivery (an operator's own reply being marked delivered/read) carries `statuses[]`
  instead of `messages[]`, under the identical `changes[].field == "messages"` discriminator** — this
  channel's own version of the hazard VK's `message.out == 1` flag solves for VK (a webhook that also
  delivers this system's own outbound activity back to it), shaped differently (a whole separate array,
  not a flag) but the same underlying risk. `WhatsAppInboundMessageParser` never reads `statuses`, so a
  status-only delivery is skipped by construction.
- **WhatsApp's own numeric error-code taxonomy for the messages endpoint**, confirmed from Meta's own
  error-codes reference: `100`/`131008`/`131009` (parameter problems), `131021`/`131026`/`131037`/`131050`
  (recipient/account refusals), and `131047`/`131049` (the 24-hour-window refusal and its
  ecosystem-quality cousin) are treated as terminal; the documented rate-limit codes (`4`/`80007`/`130429`/
  `131056`) and temporary-downtime codes (`2`/`131016`/`131057`) default to transient and are retried by
  the same resilience pipeline every other channel uses.
- **No per-call idempotency key** — Meta's own `/messages` endpoint offers no equivalent to VK's
  `random_id`. Not a WhatsApp-specific regression: MAX's and Telegram's own outbound clients already
  carry the identical gap. Named plainly rather than silently accepted: a resilience-pipeline retry after
  a transient fault could, in principle, produce a visible duplicate reply on the recipient's device.

## Tenant routing and credential ownership — decided 2026-08-30, before merge

The identical question `14-02`'s own file answers for MAX, extended to WhatsApp's genuinely different
shape: **one WhatsApp Business phone number per tenant**, the shop's own, connected through Meta's own
Embedded Signup (or a manually generated System User token) and handed to AGO as two values — an access
token and the number's own `phone_number_id` — both entered once. This reuses `ChannelCredential`
unchanged: `TokenCiphertext` holds the access token, `ProviderAccountId` holds `phone_number_id` —
confirming `ChannelCredential.ProviderAccountId`'s own prediction (written for `14-08`) that a future
channel would reuse the column rather than needing its own.

**The genuinely new wrinkle is the inbound half, and it does not transfer from any precedent.** Every
other channel resolves an inbound webhook's tenant from a `{credentialId}` URL path segment
(`GetByIdAsync`). WhatsApp's own webhook carries no such segment — it is App-wide, not per-credential
("Confirmed against Meta's own documentation" above) — so tenant attribution has to happen *after*
authentication, from the payload's own `metadata.phone_number_id`, resolved against `ChannelCredential`
via a new repository method, `IChannelCredentialRepository.GetActiveByProviderAccountIdAsync(kind,
providerAccountId)`. This is the first channel where `ProviderAccountId` is load-bearing for routing
every inbound message, not merely a value fetched once at registration the way VK's own `group_id` is.
It also motivated a new storage-level guarantee no channel needed before: a partial unique index on
`(kind, provider_account_id)` filtered to `active AND provider_account_id IS NOT NULL`
(`ux_channel_credentials_kind_provideraccountid_active`) — without it, nothing in this schema would
prevent two sites from registering the identical `phone_number_id` and one shop's visitor conversation
silently routing to another's console.

**Connecting also differs from VK's own discovery flow.** VK's `groups.getById` infers the community id
from the token alone; WhatsApp's token does not self-disclose which phone number it means (a WhatsApp
Business Account can hold more than one), so the operator supplies `phone_number_id` directly, and
`WhatsAppApiClient.GetPhoneNumberAsync` (`GET /{phone-number-id}`) validates — rather than discovers —
that the token is actually authorized for that specific number, before ever writing a `ChannelCredential`
row (the identical validate-before-write ordering VK's own connect endpoint established, for the
identical reason: nothing this call needs is generated by this system first).

**The console connect response carries neither a callback URL nor a webhook secret**, unlike VK's own
response and like MAX's/Telegram's — WhatsApp's webhook is App-wide, configured once against AGO's own
Meta App outside this endpoint entirely, so there is nothing per-credential to hand an operator.

## Scope

- A `ChannelKind.WhatsApp` value and a concrete `IInboundChannelAdapter` implementation for the Cloud
  API's webhook shape.
- Outbound reply delivery via the Cloud API's own send-message endpoint, wrapped in the same resilience
  pipeline every other channel adapter already uses, respecting the 24-hour free-form window found
  above (or naming, if the target use case never needs it, why template support is out of scope for
  this item specifically).
- Tenant routing and credential ownership, decided explicitly before code — same discipline `14-02`/
  `14-07`/`14-08` each already followed for their own channel's actual constraints.
- Console-facing connect/disconnect endpoints, matching `TelegramChannelEndpoints.cs`'s/
  `VkChannelEndpoints.cs`'s own shape.

## Out of scope

- Anything beyond a business account's own direct customer messages — WhatsApp catalogs, WhatsApp Pay,
  or any commerce-platform feature Meta's own API exposes beyond messaging.
- Message templates — decided out of scope above: the target use case never needs an outside-window
  send, so template-registration, template-selection UI and variable-substitution machinery are named as
  a real, explicit scope cut, not a silent omission.
- A resolved legal position. `0010` accepted the risk of proceeding without one; this item does not
  retroactively manufacture legal clearance by existing.

## Done when

- [ ] A real message sent to a real WhatsApp Business number reaches an operator through the same
      console queue a widget conversation already does. **Not verified live** — proven instead against
      the real production handler chain (`WhatsAppWebhookEndpointsTests`, real Postgres, real Kestrel
      host on the real `MapWhatsAppWebhookEndpoints` route, realistic fixtures built directly from Meta's
      own current documentation). What remains unverified is whether a real Meta App's own webhook
      delivery reaches this route over the public internet, and whether the field names this item
      confirmed from documentation are Meta's true shape at delivery time.
- [ ] A console reply reaches the same WhatsApp conversation back — **not verified live**, same reason.
      Proven instead against a real HTTP boundary (`WhatsAppApiClientTests`, `WhatsAppChannelAdapterTests`):
      a real message is sent, WhatsApp's own terminal/transient error-code split is honoured (including
      the 24-hour-window refusal, `131047`, surfacing as an ordinary tenant-visible refusal), and the
      outbound path is proven through the whole adapter, not just the HTTP client in isolation.
- [x] Tenant routing and credential ownership are decided and recorded, the same way `14-02`'s own
      backlog file records its equivalent decision — see "Tenant routing and credential ownership" above.
- [ ] Live verification against a real WhatsApp Business account and a real message — **no WhatsApp
      Business phone number or Meta App exists in the environment this item was built in**, the same
      honest gap `14-08`'s own file names for VK. Closing this needs a real Meta App (registered once,
      App-wide, per "Tenant routing and credential ownership" above), a real phone number connected
      through Embedded Signup, and a real public callback URL Meta can reach (this deployment's own
      public domain, matching `MaxChannelEndpoints`'/`VkChannelEndpoints`' own equivalent requirement) —
      the same live-verification pass `14-02`/`14-07` each report finding real bugs during, which this
      item's own honesty note says plainly it could not run.

## Open questions

None new. The one open question this item's own "What is already known" section named — whether
template-message support is in scope — is resolved above ("Tenant routing and credential ownership":
decided out of scope, the target use case never needs an outside-window send). The one open item left is
the live-verification pass itself, tracked as the two unchecked Done-when boxes above, not a design
question.
