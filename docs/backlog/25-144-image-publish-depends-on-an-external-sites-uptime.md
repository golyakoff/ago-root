# 25-144 · Image publish depends on an external site's uptime

- **Stage**: 25
- **Status**: done — `ago-chat#326`
- **Found**: 2026-09-18. Publishing `ago-chat`'s images failed identically five times in a row -
  `curl: (35) Recv failure: Connection reset by peer` fetching the Russian Trusted Root CA certificate
  from `gu-st.ru` at build time (`Dockerfile`, added by `14-02`). Unrelated to any of that day's actual
  code changes - `build-test` passed every time; only `publish-images`'s Docker build failed, on the
  identical step, blocking every publish behind it regardless of what merged.
- **Depends on**: none. Touches `ago-chat` only.

## Scope

Vendor the certificate as a committed file (`russian-trusted-root-ca.crt`) instead of fetching it live
on every build - the identical pattern the very next Dockerfile block already uses for
`internal-ca.crt`, and for the same reason: a certificate is public, not a secret
(`docs/architecture/secrets.md`), and this one rotates rarely (issued 2022, valid to 2032). `COPY` it
in and run `update-ca-certificates` directly; no `apt-get install ca-certificates curl` step needed,
since the base SDK image already ships both.

## Where this is likely to go wrong

- Verify the fetched certificate is genuinely the right one (subject/issuer/validity) before
  committing it - `openssl x509 -noout -subject -issuer -dates` against the file, not just "curl
  succeeded."
- Confirm the build still succeeds with the `apt-get install` line removed entirely, rather than
  assuming `update-ca-certificates` is present - build the image locally and check.
- This certificate does rotate eventually (2032) - whoever picks that up should re-fetch and re-verify
  it the same way, not assume a stale file forever.

## Done when

- [x] `ago-chat`'s Docker build no longer makes any network call to `gu-st.ru` (or any external host)
      to fetch a trust-store certificate
- [x] A full `docker build` for at least one host image succeeds locally, and the resulting image's
      trust store carries the vendored certificate (verified inside the build stage, since the final
      Chiseled stage has no shell to inspect)
- [x] CI's `publish-images` job succeeds on the next push, ending the run of failures this item was
      filed for

## Outcome

Landed and verified live the same day: after four consecutive `publish-images` failures at the
identical `gu-st.ru` step, the certificate was fetched from the (Russia-hosted) demo node instead of
GitHub Actions' own runners, verified with `openssl x509`, and committed. `publish-images` succeeded
on the very next push (`ago-chat#326`), and the resulting images were deployed to the demo stand the
same day.
