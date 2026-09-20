# 25-160 · A tenant's own company name and logo brand their reply email

- **Stage**: 25
- **Status**: done — `ago-chat#341` (commit `fc9b01c`), `ago-console#257`, ADR-0177 (`ago-root#1212`).
  The live-send box and the animated-GIF-rejection box are both settled `[~]`, not ticked - see Outcome
  and Done-when for why each is genuinely unreachable rather than merely skipped.
- **Found**: 2026-09-19, discussing `25-156` with the author. That item shipped (decided
  2026-09-18) as text-and-color only, and named a real logo feature explicitly as "a separate future
  item if it ever comes up - not built here, and not this item's own name to invent." This is that
  item.
- **Depends on**: `25-156` (extends its reply-email HTML shell to also render a logo when one is
  `ready`; `25-156`'s own text-only rendering is the fallback when none is). `25-156` itself is
  unblocked and ready independently - it does not need to wait for this item.

## What is actually true today

- `Ago.Chat.Domain.Site` carries `Name` and `WidgetConfig.PrimaryColorHex` only - confirmed by reading
  the type directly (same finding `25-156` already recorded). No logo field anywhere.
- The console's "Каналы" section (`consoleNav.ts`) has promoted three channels out of the "Другие
  каналы" catch-all into real screens so far - Telegram (`23-36`), MAX (`25-09`), VK (`25-15`), each
  "one channel end to end" per rule 15. Email is still inside that catch-all, with no dedicated screen.
- `EmailChannelAdapter` has **no per-tenant connection/credential concept at all** - it sends through
  the deployment's own configured SMTP, keyed by conversation/thread state (`IEmailThreadStore`), not
  a per-site registered account. So a real "Почта @" screen here is a **settings form**, not a
  connect/verify flow like the other three channels' own screens.
- `ago-chat` already depends on **SkiaSharp** - `Ago.Chat.Worker`'s existing
  `AttachmentThumbnailGenerator` (`5-04`) already decodes, resizes and re-encodes chat-attachment
  images with it (`SKBitmap.Decode`, `.Resize`, `SKImage.Encode`). MIT-licensed, no revenue threshold,
  no visible-attribution requirement. **No new package needed** - this item's own image validation
  reuses the identical library and the identical download/process/upload shape that generator already
  proves in production.

## Design decisions, and why (candidate ADR - see bottom)

Reached in discussion with the author before any code was written, per the project's own "grill it
before starting" habit for anything with a real architectural fork:

- **Async, via the existing outbox + `Ago.Chat.Worker` - not a new "Image Processing Service".**
  Decoding and validating a small image is a pure, stateless function; wrapping it in its own
  deployable would add a network boundary, its own scaling and its own failure mode for what is really
  a library call. `Chat.Worker` already owns exactly this class of job (attachment thumbnails), so a
  second consumer on the same broker is the additive, non-generalising choice - the platform-layer
  "premature generalisation" warning in `CLAUDE.md` applies here even though the deployable in question
  would be product-level, not platform-level. If a second *product* ever needs the same validator, that
  is the trigger to extract a shared library (the `ago-platform`-as-NuGet precedent, `adr/0012`) - not
  a hosted service, and not before that day.
- **A public, long-lived, cache-friendly URL for the finished logo - not the presigned-per-viewer model
  `IFileStorage`/attachments already use.** A chat attachment is private and short-lived by design; a
  logo is neither - it must still resolve correctly when a visitor opens a reply email weeks later, and
  it is not sensitive data needing an authorization check on every read. Reusing the presigned model
  here would mean re-signing (or expiring) a URL a mail client has no way to refresh. The stable public
  hostname `25-103` already wired for attachments (`files.reserve-me.ru`, MinIO's own S3 API) serves
  this the same way, just with a non-expiring object key and ordinary `Cache-Control` instead of SigV4
  expiry.
- **Static images only - no animated GIF.** Simpler validation (no frame-count-based abuse surface),
  and a moving logo carries no real branding value this scope needs to accommodate.
- **5 logo replacements per tenant per day**, via the existing `IRateLimiter` port
  (`Ago.Platform.Abstractions`, Redis-backed token bucket, the same mechanism `caching.md` already
  documents for message sends and widget handshakes) - a fourth, single-bucket case, not a new
  mechanism.
- **Double-cached read path**, because the two consumers of this asset have genuinely different
  profiles:
  - The **email writer** needs the raw bytes (to inline as base64, `Content-ID`, so the logo renders
    with no dependency on the recipient's own internet access at read time - the author's own point:
    mail clients are typically shown inline-embedded images, not remote-fetched ones, regardless of
    image-loading settings). This is a **server-side** read on every outbound reply, so it is protected
    by extending the existing Redis site-config cache pattern (`caching.md`'s "the hot one",
    `SiteConfigDto`): a new cache entry holds the **already-base64-encoded** payload (computed once, not
    per email), **write-through populated by the validating worker itself** the moment it finishes
    decoding the bytes (no extra storage read needed for the very first email after upload), and
    invalidated the same event-driven way `SiteSettingsChanged` already invalidates the sibling
    `SiteConfigDto` entries. A cache miss (cold Redis, expired entry) falls back to object storage -
    cache-aside, nothing new.
  - The **console's own preview / any future on-site display** reads the plain public URL directly -
    the browser's own HTTP cache absorbs repeat reads, no backend involvement at all beyond the first
    fetch.
  - Chosen over a dedicated Postgres `blobs` table: object storage already has the exact port
    (`IFileStorage`) and CDN/browser-cache-friendly HTTP semantics this needs; a Postgres table would
    still need its own caching layer in front to avoid the same "hit the database on every email" cost,
    and would additionally compete with hot OLTP tables for buffer-cache and WAL. The read-cost worry
    that motivated asking the question is real (the author's own point: object storage is temporarily
    self-hosted MinIO, but production is expected to move to a billed-per-read provider) - the double
    cache above is what actually answers it, independent of which storage backend is underneath.

## Scope

1. **Console**: promote "Почта @" out of the "Другие каналы" catch-all into a real screen
   (`/channels/email`, `EmailChannelPage.tsx`), mirroring the existing Telegram/MAX/VK promotion
   pattern - minimally, just enough to host the two fields below. No connect/credential UI: Email has
   none to add (see "What is actually true today" above).
2. That screen carries a company-name text field and a logo upload control. Client-side: accept
   `image/png,image/jpeg,image/gif`, decode locally to check real pixel dimensions (≤100×100) before
   ever uploading, and reject fast with a clear message - a courtesy check only, never the authority.
3. **New `Site` fields**: a nullable brand company name, and a logo reference (object key +
   `pending|ready|rejected` status + rejection reason). Written through the ordinary site-settings path,
   invalidating/repopulating cache the same way every other site setting already does.
4. **Upload endpoint** (`Ago.Chat.Api`, alongside the other site-config endpoints): a synchronous,
   cheap check only - raw byte-size ceiling (e.g. 200 KB) before anything is decoded - then rate-limited
   (5/site/day), then writes the bytes to a `pending` object key via `IFileStorage` and stages an
   outbox event in the same transaction that records the `pending` status. Returns immediately; no
   decode, no dimension check, happens in this request.
5. **New `Ago.Chat.Worker` consumer**, the sibling of `AttachmentThumbnailGenerator`: downloads the
   pending object (presigned GET, the same "Worker as an ordinary port consumer" shape that generator
   already uses), decodes with SkiaSharp, confirms real dimensions ≤100×100, format is one of the three
   allowed and the source is not animated (multi-frame). On success: promotes the object to its
   permanent **public** key, flips `Site`'s logo status to `ready`, publishes the existing
   site-settings-changed event, and write-through populates the new Redis branding-cache entry with the
   base64 payload it already holds in memory. On failure: flips status to `rejected` with a reason, no
   promotion.
6. **`EmailChannelAdapter`/`25-156`'s reply-email shell**: when a tenant's logo is `ready`, read its
   base64 through the new cache-aside branding lookup and inline it (`Content-ID`) in the HTML part,
   alongside the name/color `25-156` already renders. Falls back to `25-156`'s original text-only shell
   exactly as it stands today when no logo is set or it is not yet `ready`.
7. The console screen's own logo preview reads the plain public URL directly - no new mechanism, the
   same one item 2's client-side check already knows how to point an `<img>` at once uploaded.

## Out of scope

- Any other Email-channel management feature beyond hosting these two fields - there is no
  connect/credential flow to add, because the channel itself has none.
- Displaying the logo anywhere on the visitor-facing widget - a real, separate item if/when wanted; the
  public-URL storage model already accommodates it for free when that day comes.
- Animated GIF support.
- A standalone "Image Processing Service" as its own deployable - deliberately rejected, see Design
  decisions above.
- Building or measuring a CDN in front of the public MinIO/S3 hostname - the browser's own HTTP cache
  is what this item relies on; a CDN is a future, separate, measured improvement if traffic ever
  justifies it.

## Done when

- [x] Email has a real console screen (`/channels/email`) with company-name and logo fields, reachable
      the same way Telegram/MAX/VK already are
- [x] Uploading a valid ≤100×100 static PNG/JPEG/GIF succeeds, ends in `ready`, and is servable from a
      public, non-expiring URL - proven by `SiteLogoValidatorEndToEndTests` against real Postgres+MinIO
- [~] An oversized file and a wrong-format file are each rejected with a clear reason, proven by
      explicit tests (`SiteLogoValidatorEndToEndTests`) - **animated GIF rejection has no automated
      test**: SkiaSharp has no multi-frame *encoder*, so `codec.FrameCount > 1` is exercised by nothing
      but the compiler, named explicitly in that test file rather than hidden. Confirming it needs a
      real animated-GIF fixture or a manual check - left open.
- [x] More than 5 upload attempts for one site in a day are refused by the rate limiter, proven by
      `SubmitLogoUploadHandlerTests.HandleAsync_WhenRateLimited_IsRefused_BeforeAnyUpload`
- [~] A visitor's reply email embeds the tenant's own logo inline (`Content-ID`) when one is `ready`,
      and falls back to `25-156`'s text-only shell when not - proven by a real send in both states.
      **Checked and left open, not merely unchecked**: this fix's commit (`fc9b01c`) is confirmed present
      in the demo stand's deployed `ago-chat-api`/`worker` image, but `overlays/demo` has no mail-capture
      sink (mailpit is local-dev/compose only - confirmed absent anywhere on the live node) and using a
      real personal inbox in the public shared demo conversation is exactly what that page asks visitors
      not to do. The same gap `25-156` carries - no safe, real send-and-inspect path exists today.
- [x] The email-composition path does not touch object storage on a warm cache - proven by
      `EmailChannelAdapterTests.SendAsync_WithAWarmLogoCache_NeverCallsFileStorage` (a `ThrowingFileStorage`
      fake, not just an assertion on a call count)
- [x] The validating worker's write-through means the very first email sent after a successful upload
      already has a warm cache entry - proven by
      `SiteLogoValidatorEndToEndTests.ValidateAsync_WithAValidSmallStaticPng_PromotesTheLogoAndWarmsTheBrandingCache`

## Outcome

Merged 2026-09-19: `ago-chat#341` (commit `fc9b01c`) - `Site.BrandCompanyName`/`LogoObjectKey`/
`LogoStatus`, `SubmitLogoUpload`/`UpdateSiteBranding`/`GetSiteBranding`, `Ago.Chat.Worker.SiteLogoValidator`
(SkiaSharp decode/validate/promote, the sibling of `AttachmentThumbnailGenerator`), the `IPresignedUrlUploader`
port, `EmailChannelAdapter`/`TenantReplyEmailShell` inline-logo rendering via a Redis branding cache. Full
suite independently re-verified by the managing session: Domain 758, Application 1445, FakeCrm 21,
Architecture 52, Concurrency 89, Integration 1428, all 0 failed (two Docker-container-API flakes seen once
under heavy concurrent load, confirmed as environmental on a clean rerun in isolation). `ago-console#257` -
`/channels/email` (`EmailChannelPage`), 140 files / 1517 tests, independently re-verified. `ago-root#1212` -
`ADR-0177`, index row added to `docs/adr/README.md` at merge.

Two items remain genuinely open, not overlooked: the real-mailbox live-send check (needs the author/a real
inbox), and an automated animated-GIF rejection test (needs a real multi-frame fixture SkiaSharp cannot
produce itself). Neither blocks the merge; both are named above rather than silently dropped.

## Candidate ADR

The async-via-existing-worker choice and the public-URL-not-presigned access model are both the kind of
decision a reviewer would ask "why not the existing attachment pattern" about - worth `ADR-0177`,
written alongside the implementation rather than deferred, capturing the reasoning already recorded
above.
