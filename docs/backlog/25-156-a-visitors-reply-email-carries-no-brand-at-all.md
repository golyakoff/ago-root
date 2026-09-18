# 25-156 · A visitor's reply email carries no brand at all - and it should be the tenant's, not ours

- **Stage**: 25
- **Status**: ready — decided by the author, 2026-09-18: shape 1, text-and-color only, using what
  `Site` already carries. No new field, no upload path, no console screen.
- **Found**: 2026-09-18, scoping `25-155`. Carved out deliberately rather than folded in - the
  author's own reasoning: `25-155`'s emails (invite, account warnings, Keycloak's own flows) are all
  AGO's own words to AGO's own account holders, so AGO's own brand is correct there. This one is
  different in kind: `EmailChannelAdapter`'s outbound reply is an **operator's** message, relayed on
  behalf of **a tenant's own shop**, to **that tenant's own visitor** - a visitor emailing a shop
  expects that shop's identity in the reply, not "AGO Chat".
- **Depends on**: `25-155`'s own Lane A (`ago-chat`) - both this item and that lane touch
  `EmailMimeMessageBuilder.cs`/`EmailSmtpClient.cs` to add the identical `multipart/alternative`
  mechanism. Sequenced after it, not run alongside it, per the "judged on files, not topics"
  non-interference rule - this item's own worker reuses Lane A's new `BuildMultipartAlternative` method
  rather than building a second one.

## What is actually true today

`EmailChannelAdapter` (`14-09`) sends every operator reply as a real, threaded, plain-text email -
deliberately, per that item's own scope cut ("no rich HTML rendering"). A visitor who emailed a shop
and gets a reply sees an unbranded plain-text message with no indication, beyond the `From` address,
of which shop they are even talking to.

## The real question this item has to answer first

**A tenant has no stored brand identity today.** `Ago.Chat.Domain.Site` carries `Name` (a plain string)
and `WidgetConfig.PrimaryColorHex` (an optional accent color for the widget) - confirmed by reading the
type directly. **There is no logo image field anywhere.** So "brand the reply with the tenant's own
identity" is bounded by what a tenant has actually told this product about itself, and that is
currently just a name and, optionally, one color.

**Decided by the author, 2026-09-18: shape 1** - text-and-color only, ship now. The reply email's shell
uses `Site.Name` as the wordmark and `WidgetConfig.PrimaryColorHex` (falling back to a neutral default
when unset) as the one accent color - no logo, the same information the widget itself already renders
with today. A real tenant-logo feature (a new `Site` field, a presigned upload path, a console screen)
is real and bigger, and stays a separate future item if it ever comes up - not built here, and not
this item's own name to invent.

## Scope

- Wait for `25-155`'s own Lane A to land (`EmailMimeMessageBuilder`'s new
  `BuildMultipartAlternative`); this item is the second caller of that method, never a second
  implementation of it.
- `EmailChannelAdapter` builds a minimal HTML shell around the operator's own reply text: a small top
  row naming the tenant (`Site.Name`, plain text - no logo image), the reply itself as the body copy
  with no added heading or CTA (there is nothing to click, only a message), a one-line accent (e.g. a
  top border or a small label) in `WidgetConfig.PrimaryColorHex` when set, a neutral default color when
  not. Reuse layout/typography choices from `25-155`'s own shell where they still fit (fonts, spacing,
  card shape) - the two should look like siblings, not two unrelated designs.
- The plain-text part of the `multipart/alternative` body carries the reply exactly as today, unadorned
  - the same "wrapper is opt-in cosmetics, never a second copy of the reply's own meaning" reasoning
  `25-155` already states for its own multipart parts.
- Threading (`In-Reply-To`/`References`) is unaffected - the wrapper changes the body's own
  `Content-Type`, not any header `EmailChannelAdapter`'s own thread-matching already depends on.

## Out of scope

- `25-155`'s own three system/account emails and the Keycloak `emailTheme` - AGO's own brand is
  correct there, this item does not touch them.
- A real tenant-logo upload feature, or any redesign of the widget's own visual chrome - a separate,
  future item, not this one, and not implied by this item shipping.

## Done when

- [ ] A visitor's reply email renders the tenant's own name and (when set) its own accent color in a
      light HTML shell, proven by a real send
- [ ] A site with no `WidgetPrimaryColorHex` set still renders correctly, with a neutral default color
      - proven by a test, not only the happy path
- [ ] The plain-text part of the email carries the reply exactly as it does today, unadorned
- [ ] Threading (`In-Reply-To`/`References`) is proven unaffected by a real, verified reply chain
