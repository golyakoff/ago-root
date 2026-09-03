# the products cannot be deployed at all until their platform pin moves to 0.19.0

- **Stage**: 17
- **Status**: done (2026-09-04), `ago-chat#159` + `ago-calendar#33` + `ago-platform#44`
- **Found**: 2026-09-03, running the redeploy after `17-09` and `22-05` merged.

## The gap

`17-09` said a merged package is not a delivered one until the consuming repository moves its pin.
What that understated: **the node cannot build at all.** This is not a missing fix, it is a blocked
deploy.

The redeploy aborted at the image build, before applying anything — the cluster was untouched, which
is the one good thing about it:

```
NU1603  Ago.Chat.Domain depends on Ago.Platform.Kernel (>= 0.18.0) but 0.18.0 was not found.
        Ago.Platform.Kernel 0.19.0 was resolved instead.   [Warning As Error]
NU1109  Detected package downgrade: Polly.Core from 8.7.0 to centrally defined 8.5.2
NU1109  Detected package downgrade: AWSSDK.S3 from 4.0.102.4 to centrally defined 4.0.102.3
```

## Two causes, and the second is why this is more than a version bump

1. **`redeploy.sh` packs only the current platform version into the node's local feed**, and the
   Docker build resolves `Ago.Platform.*` from that feed alone (`nuget.docker.config` clears every
   other source). The moment `ago-platform`'s CHANGELOG moves ahead of a consumer's pin, that
   consumer's image cannot be built on the node.
2. **`0.19.0` carries raised transitive floors** — `Ago.Platform.Caching.Redis` wants
   `Polly.Core >= 8.7.0`, `Ago.Platform.Storage.S3` wants `AWSSDK.S3 >= 4.0.102.4` — because
   Dependabot moved them in `ago-platform` and the consumers never followed. Central package
   management turns that into a hard downgrade error rather than a silent resolve.

**CI was green throughout and would have stayed green**, because it restores from GitHub Packages
(`nuget.ci.config`) where `0.18.0` still exists. That difference between CI and the node is what made
this invisible until a deploy was attempted.

## Done when

- [x] `ago-chat` and `ago-calendar` pin `Ago.Platform.* 0.19.0`, with the transitive floors raised to
      match.
- [x] `redeploy.sh` reaches the apply step on the node. — it did, and the deploy completed with the
      full smoke suite at 45 passed, 0 failed.
- [x] The reason a platform release strands a consumer's *deploy* — not merely its fix — is written
      down where the next person to bump a platform version will see it. — in both
      `Directory.Packages.props` files, beside the pins.

## Outcome

**The third change was not planned and is the interesting one.** `17-09` made `ILogger<T>` a required
constructor parameter on `RabbitMqConnection` and `RabbitMqEventPublisher`, and its CHANGELOG said
that touched only `ago-platform`'s own tests. It did not: `ago-chat`'s `Integration` and `Concurrency`
suites construct both types directly — **38 call sites across 17 files**, and the build failed with
**41 `CS7036` errors**.

The reasoning that produced the wrong claim was itself correct — no *host* changed, because every host
resolves these through `AddRabbitMqMessaging` — which is exactly why it misled. **Hosts are not every
place a type is constructed.** A source-breaking change to a type consumers instantiate has to be
measured in the consumers, not in the package. `ago-platform#44` corrects the entry in place rather
than leaving it to mislead the next person; `--skip-duplicate` on the push step means re-packing the
same version is a no-op, checked rather than assumed.

Three of the 38 needed hand-editing: `ConnectionFanoutFixture`, `OutboxDispatcherFixture` and
`WebhookDispatchFixture` use a target-typed `new(Options.Create(new RabbitMqOptions { … }))` spanning
several lines, which the pattern that fixed the other 35 does not match.

**And two of my own verification commands nearly lied.** `dotnet build … | tail -3 && dotnet test`
takes its exit status from `tail`, not from `dotnet`, so a build that failed with 41 errors was
silently stepped over and the suite then reported "0 failed" from four of six assemblies. Exit codes
now come from the commands themselves. This is the same failure `land-a-slice` already warns about in
a different form: a truncated run is indistinguishable from a clean one unless you check which
assemblies are missing.
