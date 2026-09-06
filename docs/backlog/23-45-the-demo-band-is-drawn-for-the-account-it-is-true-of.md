# the demo band is drawn for the one account it is true of, and for nobody else

- **Stage**: 23
- **Status**: done (2026-09-06). One fact on `/api/v1/operators/me`, a startup validation behind it,
  and six tests — one per kind of reader.
- **Depends on**: nothing. Replaces the mechanism `12-04` and `23-42` were both reaching for.
- **Decision**: the author's, 2026-09-06 — *the band only for the shared demo login*, chosen from
  three options after signing in with their own tenant and being told their login is published

## What was true

`8-06` put a permanent band on every screen of the public demo console: *this is public, the login is
published, the conversations are strangers', do not type anything real.*

The author signed in with their **own real tenant** and was told exactly that. Every clause of it is
false for them: their login is published nowhere, and the conversations in their console are their
own customers'.

## Why the two previous fixes could not have caught it

`12-04` found this same shape for the platform owner and fixed it by adding a **second wording**.
`23-42` then removed the band for that reader entirely.

**Neither could fix the cause, which is that the console had no way to ask the question.** Both
inferred the answer from *who is not the platform owner* — so a real tenant got the wording written
for the shared demo shop, and so did a minted demo tenant, whose credentials are shown once on one
screen and printed on no page.

## The one fact, and why it is configuration rather than a column

`GET /api/v1/operators/me` now carries whether **this site's console credentials are printed on a
public page**. It rides on a response the console already loads at bootstrap, for the same *no second
network call* reason `locale` and `enabledModules` already do, and it costs **no extra query** — the
handler already loads the site config for the locale, and that config carries the public key.

**It cannot be derived.** Checked against the live database rather than assumed:

| | `demo_expires_at` | credentials published |
|---|---|---|
| the seeded shared demo shops (`demo_site`, `demo_site2`) | **null** | **yes** |
| a real tenant | **null** | no |
| a minted demo tenant | set | no |

The shared shops and a real tenant differ in **nothing** this question could read. The tempting
signal — `IsDemo`, which exists and is honest — answers a different question, and answering with it
would have told a minted demo tenant that their password is on a web page.

And it is not a property of the tenant in the first place: the same row on another deployment has no
password on any page. It is a property of *this deployment's* demo setup, which is where it now lives.

## The failure direction inverts, and it is paid for rather than left implicit

`12-04` was careful that forgetting the prop showed the **stricter** text. An empty list now shows
**nothing** — because *"we do not know that your password is published"* cannot honestly render as
*"your password is published"*.

So `DemoTenantOptionsValidator` **refuses to start** a deployment that mints demo tenants while
naming no published site. The guard moved from a default to a boot failure: loud where the old
default was quiet, and a crash is something somebody notices where a missing sentence is not.

It lives in `Ago.Chat.Api` rather than beside its options class because `IValidateOptions<T>` comes
from `Microsoft.Extensions.Options`, which `Ago.Chat.Application` does not reference. **The compiler
said so before the comment did** — putting the validator next to `DemoTenantOptions` failed to build,
which is the dependency rule doing its job rather than a preference.

## A cost taken knowingly

**The pre-session screens now show nothing.** `8-06` wanted this on the sign-in screen, and a reader
about to use the published login is no longer warned *before* they use it.

Accepted because nothing before sign-in knows whose account is coming; because `/signup` is where the
old wording was at its most wrong, told to somebody in the act of creating a real tenant; and because
the band appears the instant a published account lands in the console, which is before anything can
be typed into it.

## Done when

- [x] The shared demo shop sees the band, and every clause in it is true of them.
- [x] A real tenant, a minted demo tenant and the platform owner see nothing.
- [x] A shell that passes nothing draws no band, and a demo deployment naming no published site
      refuses to start.
- [x] Six tests, one per kind of reader, and four on the API side — including the minted tenant,
      asserted with its expiry actually set, so a later change reaching for `IsDemo` reddens rather
      than ships.

## Outcome

`ago-chat#205`, `ago-console#133`, `ago-deploy#151`. Deployed the same evening.

**One test change is worth more than the feature.** `consoleLocale.test.tsx`'s two band-wording tests
now sign in as a published account. Without that they would have **passed by rendering nothing** —
which is the shape of a translation test that has quietly stopped testing translation, and the reason
to re-read every green test that touches a thing you have just made conditional.
