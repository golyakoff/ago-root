# Visitor traffic-source report: where a conversation actually came from

- **Stage**: 18
- **Status**: ready
- **Depends on**: `18-08-basic-operator-analytics.md` (done) — the per-channel breakdown shape this
  item adds a second, orthogonal dimension alongside; `14-01-external-channel-identity-and-inbound-port.md`
  (done) — this item's own capture point sits beside, not instead of, channel identity

## Goal

A site owner can see which traffic source actually produces conversations — direct, a search engine, a
specific referring site, or (when the shop ran one) a named ad campaign — the half of
`ago-business/docs/decisions/0009`'s reporting gap named "источники диалогов" (dialogue sources) that
`18-08`/`18-09` do not touch at all: those two report *what channel* a conversation arrived on
(`Widget`/`Telegram`/`Vk`/…), never *what brought the visitor to the site in the first place*. Both
questions matter to a small shop and neither answers the other — a visitor can arrive at the widget
channel from an Instagram ad, a Google search, or a friend's link, and today AGO Chat cannot tell those
apart at all.

## Why this field goes on `Conversation`, not `Visitor` — read before writing any code

`docs/architecture/personal-data.md`'s own `visitors` row is explicit and bolded: `id, site_id,
first_seen_at, last_seen_at` **and nothing else** — a deliberate design boundary, not an oversight
(`personal-data.md:87-88`: `visitors` holds no structured identifier at all *by design*;
`channel_identities` was added as its own separate table precisely so `visitors` would not have to grow
one). Adding a referrer/landing-page field to `Visitor` would silently break that boundary.

The field belongs on `Conversation` instead, for a second, independent reason beyond respecting that
boundary: a **returning** visitor can arrive via a different source on every visit — the interesting
business question is "where did *this* conversation's own visitor come from right now," not "where did
this browser's very first-ever page view years ago come from." `Conversation` already carries its own
per-instance timestamps (`personal-data.md:89`); a landing source captured once at
`Conversation.Start()` is the same shape, not a new kind of thing this aggregate does not already hold.

## What to capture, and the honest limit on how much this item can promise

- The widget captures, at the moment a conversation actually starts (not at widget mount/page load — a
  widget can sit open on a page a visitor never messages through): `document.referrer` (empty when
  blocked by a privacy setting, a direct visit, or a referrer-stripping browser — a common, expected
  case, not an error) and the current page's own URL, from which UTM query parameters
  (`utm_source`/`utm_medium`/`utm_campaign`) are parsed if present.
- **Store what was actually captured, not a lossy pre-aggregated bucket.** A shop running a named ad
  campaign needs to see that campaign's own name, not just "external referral" — collapsing to a coarse
  category at capture time would throw away the one thing that makes this report worth building over
  `18-08`'s existing per-channel numbers. Bound the stored length (an adversarial or malformed URL
  should not become an unbounded write) the same way `MessageBody`'s own length cap already protects
  the write path elsewhere in this codebase.
- **This is what the browser told the widget, not a verified fact.** A referrer header is
  client-supplied and can be spoofed, stripped, or simply absent — the report's own console copy must
  say plainly that this reflects "what the browser reported," the identical honesty discipline
  `18-10`'s own operator-reported-outcome framing already holds itself to for a different reason.

## Scope

- **Domain**: `Conversation` gains an optional, immutable-after-start value object (e.g.
  `TrafficSource` — referrer host, and the three UTM fields if present, all nullable) set once in
  `Conversation.Start()`, never mutated afterward — the same "captured once, at the moment that matters,
  never revisited" shape `ChannelIdentity.FirstSeenAt` already uses elsewhere in this codebase.
- **Widget** (`ago-widget`): reads `document.referrer`/`location.href` at the point a conversation is
  actually started (the existing `StartConversation` call site), parses UTM params from the query
  string, and includes them in that request. No new endpoint — this rides the existing start-conversation
  call, the same way `14-01`'s own channel identity rides the existing inbound path rather than adding a
  parallel one.
- **A migration** adding the new nullable columns to `conversations`, and a
  `docs/architecture/personal-data.md` row update: `conversations`' existing row needs this field named
  explicitly (a referrer/URL can incidentally carry personal data — a personalised URL, a query string
  with an identifier — the same incidental-PII class `messages.body`'s own row already names), with the
  same retention shape the existing `conversations` row already has (forever, cascades from `sites`) —
  state explicitly whether that stays adequate or whether this field needs its own note, don't leave the
  question unanswered.
- **A report** extending `18-08`'s own site-wide/per-channel shape with a source dimension: grouped by
  referrer host (or `Direct` when empty) and, separately, by `utm_campaign` when present — decide
  during implementation whether these are one combined grouping or two separate ones, and record which
  and why, the same way `18-09`'s own `GROUPING SETS` decision was made explicit rather than assumed.
- Console: a new column/section on the existing `/analytics` page (`OperatorAnalyticsPage.tsx`) or a
  small dedicated block beside it — match whatever shape reads best once the actual data volume/spread
  is visible, and say which you picked and why.

## Out of scope

- Any client-side analytics/tracking library, pixel, or third-party integration (Google Analytics,
  Meta Pixel, etc.) — this item captures exactly one first-party signal the widget itself already has
  access to at the moment a conversation starts, nothing that would require the shop to install anything
  else or that would make AGO Chat a tracking vendor.
- IP-based geolocation or any other visitor-fingerprinting signal — out of this project's own privacy
  posture (`personal-data.md`'s "mostly incidental" framing for AGO Chat's own visitor data), not a
  narrower version of this item, a different one entirely if ever wanted.
- Backfilling a source for conversations that already exist — `null` for every conversation created
  before this ships, the same "no backfill migration pretends historical data it never asked for" rule
  `18-10`'s own scope states for its outcome field.

## Done when

- [ ] The widget captures referrer/UTM params at conversation start and they reach the server, proven
      by a test (including the empty-referrer case — the common one, not the exception).
- [ ] The report groups conversations by traffic source correctly against real seeded data, including a
      mix of UTM-tagged and plain-referrer and direct-visit conversations, proven by a test.
- [ ] `docs/architecture/personal-data.md`'s `conversations` row is updated to name this new field
      explicitly.
- [ ] Cross-site isolation is proven by a test.

## Open questions

Whether referrer-host and UTM-campaign are one grouping or two, and exactly which console shape
(extend `/analytics`, or a new small section) reads best — both left for the implementation to decide
and record, per the item's own Scope section above; neither changes the underlying capture or the
domain shape.
