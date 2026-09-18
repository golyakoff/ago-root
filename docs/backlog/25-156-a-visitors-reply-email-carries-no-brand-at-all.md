# 25-156 · A visitor's reply email carries no brand at all - and it should be the tenant's, not ours

- **Stage**: 25
- **Status**: needs analysis — filed to hold the idea, not yet scoped for implementation
- **Found**: 2026-09-18, scoping `25-155`. Carved out deliberately rather than folded in - the
  author's own reasoning: `25-155`'s emails (invite, account warnings, Keycloak's own flows) are all
  AGO's own words to AGO's own account holders, so AGO's own brand is correct there. This one is
  different in kind: `EmailChannelAdapter`'s outbound reply is an **operator's** message, relayed on
  behalf of **a tenant's own shop**, to **that tenant's own visitor** - a visitor emailing a shop
  expects that shop's identity in the reply, not "AGO Chat".
- **Depends on**: `25-155` only in the sense that the two should probably share the same underlying
  `EmailMimeMessageBuilder` multipart mechanism, once that exists - not a hard blocker, since this item
  could build its own multipart path first if picked up before `25-155` does.

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

Two shapes, neither chosen yet:

1. **Text-and-color only, ship now.** The reply email's shell uses `Site.Name` as the wordmark and
   `WidgetConfig.PrimaryColorHex` (falling back to a neutral default when unset) as the one accent
   color - no logo, the same information the widget itself already renders with today. Cheap, uses
   only data this product already collects, and is honestly proportionate to what a tenant has
   actually provided.
2. **A real tenant logo, uploaded once, reused everywhere.** Needs a new `Site` field, a presigned
   upload path (the same shape `docs/architecture/file-storage.md` already establishes for
   attachments/avatars), a console screen to set it, and - once it exists - the *widget itself* and the
   console's own chrome are two more places a tenant's own uploaded logo would obviously belong,
   which makes this a materially bigger item than "brand one email."

**The author's own call is needed on which of these this item actually is** - shape 1 is a real,
shippable slice; shape 2 is closer to its own product feature (`23-31`-adjacent) that this email
happens to be the first consumer of, not the reason to build it.

## Scope

Not yet defined beyond the question above - this item's own first deliverable is the author's answer
to "text-and-color now, or a real tenant-logo feature first", recorded here, before any code.

## Out of scope

- `25-155`'s own three system/account emails and the Keycloak `emailTheme` - AGO's own brand is
  correct there, this item does not touch them.
- Redesigning the widget's own visual chrome, even if a tenant logo field is the answer chosen here -
  a separate item, once a logo exists to place there too.

## Done when

- [ ] Not yet defined - depends on the author's answer to the one open question above.
