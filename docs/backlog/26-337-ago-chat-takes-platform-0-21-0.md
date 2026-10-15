# 26-337 · [ago-chat] take `Ago.Platform.Observability` 0.21.0

- **Stage**: 26
- **Status**: ready
- **Carved out of**: `26-331` and `26-336`, which shipped the behaviour in the package but not its adoption.

## Why this is its own item

`ago-chat` pins `Ago.Platform.Observability` at `0.20.0` (`Directory.Packages.props`). Until it moves to
`0.21.0`, probes and scrapes are still traced in every ago-chat host and the Jaeger ring still turns
over on them - the problem `26-331` exists to fix has not been fixed *anywhere it is observed*.

## Done when

- [ ] `Ago.Platform.*` packages bumped to `0.21.0` in `ago-chat` (all of the family, so it never skews);
      `build-test` green.
- [ ] Verified on the stand after deploy: Jaeger holds no `/healthz*` or `/metrics` root spans, and
      `http_server_request_duration` still counts them. A number, not an assertion (`CLAUDE.md` rule 7).
- [ ] `ago-calendar` checked: if it references `Ago.Platform.Observability`, bump it too; if not, say so here.
