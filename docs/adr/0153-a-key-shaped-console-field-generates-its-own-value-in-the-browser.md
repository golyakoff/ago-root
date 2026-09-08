# ADR-0153: a key-shaped console field generates its own value in the browser

- **Status**: Accepted
- **Date**: 2026-09-07
- **Stage**: 23 (`23-94`)

## Context

The platform owner's grant form (`adr/0150`) has a **Credential** field: the module's own per-site
secret, 16–256 characters (`Ago.Chat.Domain.ModuleCredential`). Nothing on the form or the server
produces one — the honest instruction was *"open a terminal and run `openssl rand -base64 32`"*, found
by the author while filling the form on a phone, where that instruction cannot be followed at all.

`ModuleCredential`'s own remarks call its length floor *"a floor against an operator typing something
trivial, not a real entropy check"* — it cannot tell a random 32-byte key from 32 repeated characters.
A person without a terminal open will type something anyway, and it will pass.

**This codebase already has an established answer to "mint a random secret", and it is server-side.**
`IWebhookSecretGenerator`, `IModuleCredentialGenerator` (used by rotation), `IOperatorInviteCodeGenerator`
and `IDemoCredentialGenerator` all mint a CSPRNG value behind a port in `Ago.Chat.Application`, called
from inside a handler. A reviewer who knows this convention would reasonably expect a fifth one here —
which is exactly the alternative this ADR has to name and reject, not merely note in passing.

## Decision

**The console generates the value itself, with `crypto.getRandomValues` — no new server route.**

`generateModuleCredential()` (`ago-console/src/owner/generateModuleCredential.ts`) draws 32 bytes from
the browser's own CSPRNG and base64-encodes them — byte-for-byte what `openssl rand -base64 32` already
produced, minus the terminal. A **Generate** button beside the Credential field fills it in the clear
(the field switches out of `type="password"`) with a **Copy** button beside that, since this is the only
moment the value can be seen at all — it is never echoed back by the server once saved
(`OwnerModuleEndpoints.GrantModuleRequest`'s own remarks).

**Never `Math.random()`.** It is not a CSPRNG, and a generator that produces a predictable secret is
worse than none, because it removes the prompt to think — proven mechanically, not just asserted: a test
makes `Math.random` throw if the generator's own code path ever reaches it at all.

**The generated value is exactly what reaches the request body.** It lands in the identical `credentialInput`
React state `handleGrantSubmit` already reads, trimmed the same way a hand-typed value is — there is no
second "generated value" the form has to remember to adopt, no path where it is silently regenerated,
re-rendered, or altered between the click and the submit. A test follows one generated value from the
click through to the exact object `grantOwnerModule` is called with.

## Why this line and not the server-side convention

**Every existing generator mints a value the server itself needs to own, verify, or act on inside the
same request.** `IWebhookSecretGenerator`'s value is stored and later HMAC-compared by that same server;
`IModuleCredentialGenerator`'s rotation mints, calls the module, and persists — one atomic handler, no
round trip to a browser in between; `IOperatorInviteCodeGenerator`'s code is looked up against a stored
row. In every one of those, generating server-side is simply where the value already has to exist.

**The grant form's credential is different: nothing server-side needs to produce it.** It is accepted
as opaque caller input exactly the same way a hand-typed value already was — `ModuleCredential` validates
shape only, never meaning (`ModuleCredential`'s own remarks), and the handler that receives it does not
care whether a human typed it or a CSPRNG did. Minting it on the server would add an authenticated round
trip whose only job is "give me a random string" — the browser can already do that itself, with the
identical guarantee (`crypto.getRandomValues` is a real CSPRNG, present in every browser this console
supports), for a value that then has to travel back across the network anyway before it is useful. Fewer
parties see the plaintext this way, not more: it exists only in the platform owner's own browser until
the moment they submit it.

## Consequences

**Positive.** A key-shaped field can be filled without leaving the browser, with a value from a real
CSPRNG — the friction that produced a weak secret (typing something trivial because a terminal was not
at hand) is gone, not merely documented as a support instruction.

**Negative, and named.**

- **A second way to produce "a random module credential" now exists in this codebase** — one in the
  browser (this item), one on the server (`IModuleCredentialGenerator`, rotation) — where a reader
  might reasonably expect one mechanism reused twice. They are not unified because they solve genuinely
  different problems (a value a form needs to show a human before submitting it, versus a value a single
  atomic handler mints and immediately uses) - see "Why this line and not the server-side convention"
  above.
- **The console, not `Ago.Chat.*`, now owns one CSPRNG call.** A future audit of "where does this
  codebase generate secrets" has to know to look in two repositories, not one.
- **Generalises to any future key-shaped field, not only this one** — the item's own scope names this
  explicitly. The next field of this shape gets the identical control for the identical reason, rather
  than reopening this argument from nothing.

## Alternatives considered

**A server route that mints and returns a value, the identical shape rotation already uses.** Rejected:
it would add a new authenticated round trip for a capability the browser already has, natively, with no
weaker guarantee - `crypto.getRandomValues` is not a lesser CSPRNG than `RandomNumberGenerator` on the
server, only a different process running it. The value would also transit the network one more time
than it needs to, before the platform owner has even decided to submit it.

**Leave the field as-is, only fix its documentation.** Rejected outright, and rejected by the author's
own framing: a floor that cannot tell a random key from a trivial one, paired with an instruction nobody
on a phone can follow, is the friction that produces a weak secret - documenting it more clearly does
not remove the friction.

**`Math.random()`.** Rejected, explicitly, as disqualifying rather than merely inferior - see Decision.
