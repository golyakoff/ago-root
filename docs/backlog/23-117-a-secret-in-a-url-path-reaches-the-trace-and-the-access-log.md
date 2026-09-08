# a secret in a URL path reaches the trace and the access log

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing. Found while reviewing `23-70`, which is the first change that would have created this exposure.
- **Found**: 2026-09-08, and **confirmed against the live stand rather than reasoned about**.

## What was measured, not assumed

An `Ago.Chat.Api` span pulled from the running Jaeger on the demo node carries these attributes:

```
http.route  = /hubs/operator/negotiate
url.path    = /hubs/operator/negotiate                          <- verbatim
url.query   = ?activeSite=Redacted&negotiateVersion=Redacted    <- values already redacted
```

So in the OpenTelemetry ASP.NET Core instrumentation this deployment runs (1.18.0, wired by
`Ago.Platform.Observability` with no filter or enrichment of any kind):

- **query-string values are redacted by default**, and
- **path segments are recorded verbatim**.

`23-70`'s first implementation put an invite code — a 256-bit secret that grants access to a tenant's
account — in a GET path. It would have reached Jaeger in clear. That endpoint was changed to a POST
before landing, so **no such exposure exists today**; this item is about the general case, which is
now known to be sharp rather than theoretical.

**The belief this corrects is worth recording.** The reviewing worker's own report stated that a query
parameter would be captured too, so path-versus-query made no difference. The live span says otherwise.
A library default is something to check against the running system, not to infer from documentation.

## Why this is not closed by "do not do that"

Nothing stops the next endpoint doing it. There is no check, no convention document that says it, and
the one deployment-wide place that could enforce it — `Ago.Platform.Observability` — configures no
redaction at all. `api-design.md` is silent on where a credential may appear.

The second surface is untested: **NGINX Gateway Fabric's own access log**, which records request paths
at the edge, before any application setting applies. Nobody has looked at what it retains or for how
long. The console's `/invite/:code` browser route still puts a code in a path there by necessity — a
link has to be a link — so this surface is live regardless of what the API does.

## Scope

- **A convention, written where somebody will meet it**: a credential travels in a body or a header,
  never in a path; `api-design.md` is the place, and `23-70`'s POST-that-reads is the worked example
  with its reasoning.
- **What the edge retains is established** — the access-log format, whether paths are kept, and for how
  long. Then decided, rather than left as "probably fine".
- **Whether `Ago.Platform.Observability` should redact known-sensitive path segments** is answered
  either way. It is a platform concern and it would protect every product at once, which is the
  argument for; the argument against is that a redaction list is a thing to maintain and to forget.

## Where this is likely to go wrong

- **A redaction list gives false comfort.** Anything it does not name is captured verbatim, and nobody
  is told. If that route is taken, it needs a way to notice a route it does not cover — otherwise it is
  the "control believed to be running" shape this project has now hit three times.
- **Do not rely on query-string redaction being permanent.** It is a default of one library version. If
  a credential ever has to be in a URL, that fact should not be what protects it.
- **The browser's own history and the clipboard are not covered by any of this**, and `23-70`'s item
  already accepted that risk class for the invite link. This item does not reopen it.

## Done when

- [ ] Where a credential may and may not appear is written down, with `23-70`'s POST as the example.
- [ ] What the edge access log retains is established by looking, and recorded.
- [ ] Whether the platform redacts path segments is decided either way, and if it does, there is
      something that notices a path it does not cover.
