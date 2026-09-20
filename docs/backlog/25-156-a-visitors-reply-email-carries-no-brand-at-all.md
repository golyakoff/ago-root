# 25-156 · A visitor's reply email carries no brand at all - and it should be the tenant's, not ours

- **Stage**: 25
- **Status**: done — `ago-chat#336` (commit `b189c64`), confirmed genuinely deployed to the demo stand.
  The real-mailbox live-send box is settled `[~]`, not ticked - no mail-capture sink exists on
  `overlays/demo` and a real personal inbox has no safe way to be used in the public shared demo. Decided
  by the author, 2026-09-18: shape 1, text-and-color only, using what `Site` already carries. No new
  field, no upload path, no console screen.
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

- [x] A visitor's reply email renders the tenant's own name and (when set) its own accent color in a
      light HTML shell - proven by a test decoding the real rendered HTML from the wire transcript.
      Not yet proven by a real send (see the open box below)
- [x] A site with no `WidgetPrimaryColorHex` set still renders correctly, with a neutral default color
      - proven by a test, not only the happy path
- [x] The plain-text part of the email carries the reply exactly as it does today, unadorned - proven
      by a test
- [~] Threading (`In-Reply-To`/`References`) is proven unaffected by a real, verified reply chain -
      header-level tests pass. **Checked and left open, not merely unchecked**: the managing session
      confirmed this fix's own commit (`b189c64`) is genuinely present in the demo stand's currently
      deployed `ago-chat-api`/`worker`/`webhooks` image (`git show 177be3f7...:...TenantReplyEmailShell.cs`),
      then looked for a way to actually send and read a real reply email there. `overlays/demo` has no
      mail-capture sink at all - mailpit exists only in `overlays/local` (local dev) and the docker-compose
      loop, confirmed by `grep -r mailpit` across `ago-deploy` and by finding no such pod/service/container
      anywhere on the live node. The only other way to see a real rendered reply is to give a real personal
      inbox as the visitor's own contact detail in the public, shared demo conversation - which is exactly
      what that page's own banner asks visitors not to do ("не указывайте реальные данные"). Left `[~]`
      rather than ticked: no safe, real send-and-inspect path exists on the current demo deployment.

## Outcome so far

Fixed and merged 2026-09-19: `TenantReplyEmailShell` (new, `Ago.Chat.Infrastructure.Email`) renders
`Site.Name` and `WidgetConfig.PrimaryColorHex` into a light HTML shell, a deliberate smaller sibling of
`25-155`'s `EmailHtmlShell` rather than a second call into it (that shell's logo row and footer text
are both wrong for a tenant-branded reply - see the new type's own doc comment). `EmailChannelAdapter`
now loads the conversation's `Site` and attaches the shell as `HtmlBody`, reusing `25-155`'s
`BuildMultipartAlternative`. 9 tests (4 new, 5 existing extended for the new dependency), all green;
5 new tests fails-before/passes-after proven. `ago-chat#336`, commit `b189c64`. The remaining Done-when
box (a real, live send through a threaded reply chain) needs a live mailbox this session did not use -
left open rather than ticked or split off.
