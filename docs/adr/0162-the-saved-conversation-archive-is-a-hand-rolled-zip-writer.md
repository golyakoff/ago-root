# ADR-0162: The saved-conversation archive is a hand-rolled ZIP writer, not a library

- **Status**: Accepted
- **Date**: 2026-09-09
- **Stage**: 23 (`backlog/23-62-a-visitor-can-keep-a-copy-of-the-conversation.md`)

## Context

`23-62`'s decision (recorded in the backlog item itself) is that a visitor's saved conversation is a
`.zip` containing an HTML transcript plus the real attachment files, not links to them. The item's own
"Where this is likely to go wrong" section named the risk before any code existed: building a `.zip`
client-side needs *something*, and that something is not free against `ago-widget`'s hard, CI-enforced
bundle-gzip ceiling (`embeddable-widget` skill; 45 KB today, ~32 KB already spent before this item).

The browser ships `CompressionStream`, a platform API with no polyfill needed, Baseline across every
browser this widget targets. `"deflate-raw"` mode produces raw DEFLATE output - byte-identical to what
the ZIP format's own compression method 8 already expects, no zlib wrapper to strip. What it does not
give is a ZIP *container*: the local file header, central directory and end-of-central-directory
record are each small, fully specified binary layouts, and neither the container framing nor the
CRC-32 checksum ZIP stores per entry is exposed by any Web API.

The alternative most teams would reach for here is a small npm package (`jszip`, `fflate`, and similar
have compressed-blob writers built for exactly this). That is the pragmatic, default choice, and it is
what this ADR argues against.

## Decision

`ago-widget/src/modules/saveConversation/zip.ts` writes ZIP archives by hand: a CRC-32 table and
routine (~15 lines), a `DataView`-based writer for the three ZIP structures (~150 lines), and a thin
wrapper around `CompressionStream("deflate-raw")` for the one part of the format an npm package would
otherwise also have to implement or bundle. If `CompressionStream` is unavailable or throws, the
writer falls back to ZIP method 0 (store, i.e. uncompressed) for that entry - the archive is still
valid, only bigger, never absent (`embeddable-widget` skill's "never break the host page").

No dependency is added. `package.json`'s `dependencies` stay exactly what they were before this item
(`@microsoft/signalr` alone).

## Consequences

**What this buys.** Zero new bytes of dependency risk (supply-chain surface, license review, transitive
updates) for a feature most visitors never trigger, and the lazy chunk this code lives in
(`dist/widget-module-save.js`) measures 2.51 KB gzipped - not counted against the base bundle's own
budget at all, since it loads only on click (`ui/moduleLoader.ts`'s runtime `import()`, proven absent
from the base bundle by `bundleInputs.test.ts`).

**What it costs.** ~200 lines of binary-format code that this repository now owns and must keep
correct - a category of bug (an off-by-one in a header offset, a wrong endianness) that a maintained
library would have already found and fixed for every one of its users, not just this one. It is tested
by hand-parsing the produced bytes back apart (`zip.test.ts`, `node:zlib`'s `inflateRawSync` as the
independent counterpart to `CompressionStream`), which is real coverage but is this project's own
coverage, not a library's accumulated field experience. A future ZIP feature this writer does not yet
need (streaming for very large archives, a Zip64 extension for files past 4 GiB, an archive comment)
is a feature this repository would have to add itself.

## Alternatives considered

**A general-purpose ZIP library (`jszip`, `fflate`).** Rejected on the numbers, not on principle:
`fflate`'s own ZIP writer alone is a comparable amount of code to what is written here, plus it ships
its *own* DEFLATE implementation (JS, not the browser's native one) because it cannot assume
`CompressionStream` - duplicating work the platform already does for free, at real gzipped-bundle cost,
for a widget that is gzip-budget-constrained specifically. `jszip` is heavier still. Either would have
been the right call in a codebase without a hard, CI-enforced bundle ceiling; this one has one, and the
budget is the reason `23-62`'s own backlog item asked this exact question before implementation began.

**A server-side archive endpoint** (the visitor asks the API for a `.zip`, the API streams it back).
Rejected because it moves the trust boundary: the server would need to fetch every attachment's bytes
on the visitor's behalf and hold them in memory or temp storage long enough to zip them, for a feature
whose entire benefit is "the file is exactly what is already on this visitor's own screen" - nothing
here needs a new authenticated endpoint or a new load pattern on `Ago.Chat.Api`. It would also make the
attachment-CORS gap this item's own code found (`archive.ts`'s remarks on `fetchAttachmentBytes` -
`IFileStorage`/MinIO configures no bucket CORS policy today, so a client-side `fetch()` of a presigned
GET can fail where an `<img src>`/`<a href>` navigation would not) somebody else's problem to solve
later rather than a documented, gracefully-degraded limitation today.
