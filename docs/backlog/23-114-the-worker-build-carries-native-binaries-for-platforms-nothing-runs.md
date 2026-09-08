# the worker build carries native binaries for platforms nothing runs

- **Stage**: 23
- **Status**: ready
- **Depends on**: nothing.
- **Found**: 2026-09-08, by the author, from memory of an early rule while the workspace was being reclaimed.

## What the author remembered, and what is actually true

> We had a rule early on — do not drag `libSkiaSharp` builds for *all* platforms into the image;
> that is 500 MB in every `ago-chat`. Then we lost it somewhere.

**The rule about the image did not get lost.** The published `ago-chat-worker` image is **67 MB** and
carries no `runtimes/` tree at all — checked against the registry on the node, not assumed. Whatever
the Dockerfile does about this, it is still doing it.

**What nobody was watching is the local build**, and there the memory is right about the size:

| | |
|---|---|
| `src/Ago.Chat.Worker/bin/Release/net10.0/runtimes/` | **440 MB** |
| of which `win-x86` | 98 MB |
| of which `win-x64` | 97 MB |
| of which `win-arm64` | 93 MB |
| `Ago.Chat.Api`, `Ago.Chat.Webhooks` | none — only the Worker references Skia |

**This machine is `AMD64`.** So `win-x86` and `win-arm64` — **191 MB** — are native binaries for
platforms that neither the container nor this developer's machine will ever load, and they are copied
into every `ago-chat` worktree that gets built.

## Why it is worth a number even though the image is fine

Not for the disk on its own — `23-111` reclaimed 100 GB by removing merged worktrees, which dwarfs
this. It matters because **the waste is per-build and recurs**, where the worktree accumulation was a
one-off backlog now under a script. Every `dotnet build -c Release` on a fresh worktree writes another
440 MB, of which 191 MB is provably unusable.

## Where the packages come from

`Ago.Chat.Worker.csproj`, with its own comment from `5-04` explaining the split:

- `SkiaSharp` — the managed binding.
- `SkiaSharp.NativeAssets.Linux.NoDependencies` — for the container image.
- `SkiaSharp.NativeAssets.Win32` — *"for local `dotnet run`/tests on this dev machine"*.

That third one is the source of all three Windows runtime folders, and its stated purpose names one
machine and one architecture. The remaining ~150 MB (osx, linux-bionic, linux-musl, riscv64 and the
rest) arrives with the packages regardless and is a separate question from the Windows three.

## Where this is likely to go wrong

- **Do not narrow this by removing `SkiaSharp.NativeAssets.Win32`.** Local `dotnet run` and the
  thumbnail tests need it, and its comment says so; the fix is narrowing *which* Windows runtimes are
  restored, not dropping Windows.
- **Whatever is chosen must not change what the image contains.** The image is correct today, and a
  `RuntimeIdentifier` set carelessly is a well-known way to change what gets published.
- **CI runs on Linux.** A condition written as "Windows only" must still leave CI building and testing
  exactly what it builds now, and that is the thing to demonstrate rather than assert.
- **`AttachmentThumbnailGenerator` is the only consumer.** If its tests pass on a narrowed restore,
  the narrowing is real; if they are skipped on the platform in question, it proves nothing.

## Done when

- [ ] A `Release` build of `Ago.Chat.Worker` no longer writes native binaries for platforms that
      neither this machine nor the container can load, and the new size is recorded next to the 440 MB
      above.
- [ ] The published image's contents and size are unchanged, checked rather than assumed.
- [ ] The thumbnail tests still exercise Skia for real on both this machine and CI.
