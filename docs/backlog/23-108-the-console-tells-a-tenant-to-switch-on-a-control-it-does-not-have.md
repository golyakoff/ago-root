# the console tells a tenant to switch on a control it does not have

- **Stage**: 23
- **Status**: done
- **Depends on**: nothing. Found while sweeping `23-107`'s guidance strings.
- **Found**: 2026-09-08, sweeping every string that tells a tenant to go somewhere.

## What a tenant reads

On the documents screen, on the contact-consent panel, when the document is not being enforced:

> Пока не требуется — включите «Требовать согласие перед сбором контактных данных» в настройках
> виджета, иначе это никого не связывает

Rendered with `badgeTone="danger"`, so it is the loudest thing on the panel.

## Why it cannot be followed

**That control does not exist.** The quoted phrase appears exactly once in the whole console — in
this sentence. There is no field, no label, and no string for it on the widget-settings screen or
anywhere else.

The setting itself is real: `Site.WidgetConfig.RequireContactConsent` is enforced by the API
(`GetConsentRequirement`, and `ConversationErrors`' `AgreementUnavailable`), and it is carried on
the widget-config endpoint's request and response (`WidgetConfigEndpoints.cs`). The console reads
it — `siteConsentDocumentsApi.ts` exposes `contactConsentRequired` — and never writes it.

So a tenant is told, in the strongest tone the component offers, to do something the product does
not let them do. `23-107`'s rule was that a screen name is not a path; this is the harder case,
where no path exists at the end of it.

## Why it is not merely cosmetic

A tenant who publishes a contact-consent document reasonably believes they have done the thing the
screen asked of them. The panel then tells them it binds nobody, and offers no way to change that.
Whether consent is actually collected before a phone number is captured is exactly the kind of
question where believing you have configured something and not having done so is worse than knowing
you have not.

## The readings — this is the part that needs the author

1. **The console gains the control.** The endpoint already accepts it, so this is a field on the
   widget-settings screen and nothing more. It makes the instruction true as written.
2. **Requiring consent stops being optional** when a contact document is published — the flag becomes
   a consequence of publishing rather than a separate switch, and the sentence disappears instead of
   being fixed. Fewer controls, but it takes a choice away from a tenant who may have one document
   for one jurisdiction and different rules elsewhere.
3. **The sentence is corrected to say what is actually true** — that enforcement is not yet available
   from the console — and the control is filed separately. Cheapest, and honest, but it leaves the
   product with an enforced setting no owner can reach.

**This item does not pick.** Reading 2 is a product decision about what a published document means,
and reading 1 quietly answers it the other way by shipping a switch. Both are choices the author
makes, not the implementer.

## Done when

- [x] **Reading 1**, chosen by the author: the console gains the control. Recorded in the change
      itself - `WidgetConfigPage`'s new field, and the doc comment on
      `UpdateWidgetConfigRequest` explaining what a gate is and why only this field is required.
      Reading 2 was declined because it decides what publishing a consent document *means*, which is a
      product and legal question rather than an implementer's.
- [x] The control exists, on the widget screen the sentence already named, and the sentence now
      carries a real `<Link>` to it rather than the screen's name in prose - `23-107`'s rule. A test
      asserts that link, bound to the nav's own string so a rename cannot make the sentence wrong
      again; it caught my own assumption, since the menu reads "Website widget" and not "Widget
      appearance".
- [x] Reachable. **And the item was filed a defect short**, which is the part worth recording:
      `WidgetConfigDto` carried no `requireContactConsent` while the server's request took a
      non-nullable `bool`, and the page serialises that object as the *entire* PUT body - so an absent
      property bound to `false` and **saving a colour would have silently switched off a consent gate
      the API genuinely enforces**. It had no symptom only because nothing could turn the gate on:
      the same defect from the other side, and fixing the control alone would have shipped a setting
      that cleared itself on the next save. Both halves are closed, each with a test shown biting.
