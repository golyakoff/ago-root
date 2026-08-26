# ADR-0067: one key issues, several validate, and retirement is a configured delay

- **Status**: Accepted
- **Date**: 2026-08-27
- **Stage**: 17

## Context

`17-03`'s audit found that this system's secret *handling* is genuinely sound — `ago-deploy` carries
`.example` files only, `git ls-files` finds no tracked `.env`, and secrets reach the cluster through a
`secretGenerator` reading a file that exists only on the machine doing the deploy. What did not exist
was any story for *changing* a secret, and one of them turned out to be far more expensive to change
than anything else in the inventory.

`Ago.Chat.Api` signs visitor tokens with a single symmetric key (`Auth:SigningKey`, from
`AUTH_JWT_SIGNING_KEY`) shared by every site. **The only key that validated was the only key that
signed.** So changing it invalidated every outstanding visitor token, for every site, at the same
instant: every visitor in the system loses their session and their conversation continuity
simultaneously. There is no per-token revocation and deliberately none planned (`adr/0034`), so this
key *is* the revocation mechanism — and it is one nobody will ever pull, because pulling it is a
customer-visible incident. A key that cannot be rotated has an effective lifetime of "forever", which
is the actual finding.

Three facts constrain the answer, and all three are already decided elsewhere.

**The drain window is seven days, and it is derived rather than chosen here.**
`JwtTokenService.VisitorTokenLifetime` is seven days (`17-08`/`adr/0048`). That is the longest an
honest visitor can still be presenting a token signed by an outgoing key, so it is the shortest window
that can pass before the old key stops being accepted without evicting somebody who did nothing wrong.

**That number has already moved once.** `17-06`/`adr/0034` kept it at thirty and named the renewal
path as what would let it drop; `17-07`+`17-08`/`adr/0048` built that path and set it to seven. A
number with a demonstrated history of changing does not belong in the validation path as a literal.

**The minting endpoint is public and unauthenticated by design** (`api-design.md`, `adr/0034`).
Anyone who can read a visitor token off a page can mint their own for the same site. So this key does
not protect access to the product; what it protects is the binding to *one existing conversation's*
history. That is worth stating because it sets the honest severity of everything below.

## Decision

### One key issues; a set validates

`Auth:VisitorSigningKeys` replaces a single key with a list of entries, each with an `Id`, a `Value`
and an optional `RetiredAt`.

- **The key that issues is the one entry with no `RetiredAt`, and there must be exactly one.** Zero or
  two is a refusal to start. Not "the first", not "the newest by id": a rule that picks a winner from
  several candidates is a rule that can pick the wrong one silently, and "which key signed this token"
  must have one answer that configuration states rather than an ordering implies.
- **The keys that validate are the active key plus every retired key still inside its drain window.**
- **A key is retired by giving it a `RetiredAt`**, not by deleting it. It keeps validating until
  `RetiredAt + RetirementDelay` and then stops **on its own, with no second deploy** — which is the
  property that makes the procedure finishable. A rotation that requires someone to come back a week
  later and remove a line is a rotation that ends with the old key still accepted.

`JwtTokenService` takes the key ring and can reach only `Signing`. It is never handed the validation
set, because a service that could reach a retired key could sign with one.

### The retirement delay is configuration, with a floor

`Auth:VisitorSigningKeys:RetirementDelay` defaults to `JwtTokenService.VisitorTokenLifetime` and may
be set longer. **It may not be set shorter, and the host refuses to start if it is** — refused rather
than clamped, because silently widening a number an operator chose is how a configuration surface
stops meaning what it says.

The asymmetry is the reason there is a floor at all. Too long only means a leaked old key stays usable
for longer than necessary. Too short evicts visitors holding tokens that are still legitimately valid
— the same mass logout this whole mechanism exists to prevent, arriving a few days after the rotation
that caused it and therefore much harder to attribute.

This is the bullet `17-03` asked for by name: the seven days is safe to change again because changing
it is a configuration edit, not a release.

### The validation set is resolved per token, not captured at startup

`TokenValidationParameters.IssuerSigningKey` became `IssuerSigningKeyResolver`. This is the single line
that makes the mechanism real rather than decorative: the former is one key captured while the host is
starting, the latter is a delegate the JWT handler calls on every token. A retired key therefore leaves
the accepted set the moment its window closes — no restart, no redeploy, no operator action.

### `kid` is a diagnostic and never a decision

Each entry's `Id` is written into the JWT header, so a token can be traced to the key that signed it.
The resolver **ignores it** and returns the whole current set for the handler to try.

Requiring the header to name a configured key would reject every token minted before ids existed
(which is the entire population on the day this ships) and would turn any disagreement between a
token's `kid` and an operator's relabelling of the same key value into precisely the mass logout being
designed against. Trying two or three HMAC-SHA256 keys costs one hash each.

### Three configuration forms, and the ambiguous combination is a startup failure

1. `Auth:VisitorSigningKeys` — the rotatable form.
2. `Auth:SigningKey` — the single-key form already deployed, mapped to a set of exactly one active
   key. Kept so that **shipping this change rotates nothing and logs nobody out**; a deployment moves
   to form 1 at its first rotation and not before.
3. Neither — a random per-process key, `3-06`'s original behaviour, still correct for the
   single-instance `dotnet run` loop and still wrong for more than one replica.

**Forms 1 and 2 both set is a refusal to start, not a precedence rule.** A rotation is a hand-edit made
under time pressure, and the failure mode worth designing against is the half-finished one that adds
the key set and forgets to remove the old setting. Preferring one silently would make that edit *look*
applied while the host went on signing with the other key.

### Where the key ring lives, and why it is not an Application port

`Ago.Chat.Api/Auth/`, beside `JwtTokenService` and the schemes. `clean-architecture.md`'s port rule is
that an external resource sits behind an interface declared in `Application/Abstractions` — this is not
that. No use case issues or validates a token, and the types in the signature come from
`Microsoft.IdentityModel.Tokens`, which Application may not see. Authentication is a host concern here,
the same reasoning that already keeps `JwtTokenService` out of `Ago.Chat.Module`.

It is still an interface rather than a class read straight from `IConfiguration`, for two reasons that
are not style. The set is answered per validation against a clock, so the behaviour worth proving is a
statement about time passing — behind an interface that is a fake clock and three lines, and against a
class reading the ambient clock it is not testable at all. And `Program.cs` needs the same object in
two places (the token service and the bearer options), which is a dependency, not a lookup.

## Consequences

- **The signing key is rotatable without a mass logout, and the procedure is finishable.**
  `docs/runbooks/secret-rotation.md` carries it; `architecture/secrets.md` records what it costs
  relative to every other secret here.
- **A leaked *old* key stays usable for the length of the drain window.** This is the price of the
  mechanism and it is not hidden: seven days after a rotation, a key that leaked before it is still
  accepted. The lever for a key known to be compromised is therefore to set `RetiredAt` far enough in
  the past that the window is already closed — which *is* the mass logout, taken deliberately, for the
  one case that warrants it. That case is in the leak procedure, and it is the only place in this
  system where the blunt instrument is the right one.
- **A rotation is two config edits and a rollout, and it can be got wrong in exactly three ways, each
  of which is now a host that will not start** rather than a silent misbehaviour: two active keys, no
  active key, or both configuration forms set. `Program.cs` resolves the ring eagerly for that reason
  — a singleton is otherwise constructed on the first request that needs it, which would turn a botched
  rotation into one visitor's 500 instead of a failed rollout.
- **`adr/0034`'s "global revocation already exists" sentence is now less true, and better.** Rotating
  the key no longer invalidates every token by construction; it does so only if the operator chooses a
  `RetiredAt` in the past. That is a capability gained and a side effect lost, and the leak procedure is
  where the difference is written down.
- **Tokens now carry a `kid`.** A few bytes larger, and one more thing visible to anyone who decodes a
  visitor token. It names a key, never a value, and the ids are chosen to be non-secret labels
  (a rotation date reads best).
- **The wiring in `Program.cs` is still not covered by a test.** `VisitorKeyRotationTests` transcribes
  the scheme's configuration rather than booting `Ago.Chat.Api`, exactly as `TokenSchemeSeparationTests`
  and `VisitorSessionRenewalTests` already do — standing up the real host would need Postgres, RabbitMQ,
  Redis and MinIO to prove something about key selection. So the *mechanism* is proven and the *wiring*
  is reviewed. Stated here rather than left for a reader to discover.
- **Nothing has been rotated.** This ADR builds the mechanism; performing a rotation against the live
  deployment is a separate, deliberate act.

## Alternatives considered

- **Leave it single-key and treat rotation as an incident.** The status quo, and the honest description
  of it is that the key is never rotated. Rejected: a revocation mechanism nobody will ever pull is not
  a revocation mechanism.
- **A hard-coded seven-day drain window.** Simpler, and wrong for a number that has already moved from
  thirty to seven inside this same stage. The whole reason `17-03`'s scope names this explicitly is that
  the next change to the token lifetime should not need a release to the validation path.
- **Strict `kid` matching**, rejecting a token whose header names no configured key. Cheaper per
  validation, and it breaks every token minted before ids existed — i.e. the entire population on the
  day it ships — while adding a second way for a relabelled key to log everybody out.
- **Asymmetric keys (RS256/ES256) with a JWKS endpoint**, the shape Keycloak already uses for operator
  tokens. Genuinely better for a multi-party system: nothing that only *verifies* needs the private
  key. Rejected as out of proportion here — one issuer and one verifier, both inside `Ago.Chat.Api`, so
  the property it buys has no beneficiary yet. It also changes the token format for every visitor
  holding one, which is a migration this item would have to run *before* it had a rotation mechanism to
  run it with. The trigger that changes this answer: a second service that must verify visitor tokens
  without being able to mint them.
- **A per-site signing key** instead of one shared by every site. It would make a rotation blast-radius
  one tenant. Rejected here as a much larger change than a rotation mechanism — key material per `Site`
  is a schema change, a cache, and a new thing to back up — and it answers a different question, which
  is worth its own item if tenant-scoped key material is ever wanted for another reason.
- **Deleting the retired key from configuration once the window closes**, rather than letting it expire
  by date. That is what "rotation" means in most hand-written procedures, and it is why most of them are
  never finished: the last step happens a week later, when the incident is over and nobody is looking.
  Expiry-by-date makes the last step happen whether or not anyone remembers it.
- **Keeping `Auth:SigningKey` as a precedence rule** (key set wins when both are set) instead of a
  refusal. Rejected above: it makes a half-finished rotation edit look applied.
