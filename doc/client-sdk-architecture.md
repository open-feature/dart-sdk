# Dart Client SDK Architecture

## Status

Proposed architecture for maintainer and community review.

The normative baseline for this proposal is
[OpenFeature v0.9.0](https://github.com/open-feature/spec/releases/tag/v0.9.0).
Pinning the released specification keeps requirement identifiers and tests
reproducible. Adopting a later specification requires an explicit gap analysis
and an updated matrix; v0.9.0 is a baseline, not a permanent ceiling.

The specification marks some relevant areas as hardening or experimental. The
conformance matrix records those maturity levels so an implemented requirement
is not presented as more stable than its normative section.

## Decision

Evolve the Dart SDK repository into a monorepo that publishes independent
server-side and client-side packages. The client package implements the
OpenFeature static-context paradigm and runs in pure Dart web applications
without a Flutter dependency.

The existing server package and public API remain supported. A Flutter package
is not part of the initial split. Flutter-specific lifecycle or widget support
may be added later as a thin adapter over the pure Dart client package when a
demonstrated integration need justifies it.

## Goals

- Preserve the existing `openfeature_dart_server_sdk` package and public API.
- Publish a framework-neutral `openfeature_dart_client_sdk` package.
- Support pure Dart web and consumption from Flutter mobile, web, and desktop.
- Keep server, client, provider, and optional Flutter dependency graphs clear.
- Conform to the applicable v0.9.0 static-context requirements.
- Allow providers to reconcile cached flag state when client context changes.
- Give each published package independent versioning and release automation.
- Validate the client contract with at least two independent provider
  implementations before the first stable client release.

The two-provider gate is a project quality requirement, not a normative
OpenFeature requirement. It reduces the risk that one vendor's transport,
cache, authentication, or telemetry design becomes the implicit core API.

## Non-goals

- Moving vendor-specific providers into the core SDK repository.
- Embedding Flutter, platform-channel, or UI dependencies in the client SDK.
- Defining a generic conversation, voice, or customer-engagement abstraction.
- Using feature flags as a workflow engine or message transport.
- Requiring server and client packages to release at the same version.
- Renaming the repository or relocating the server package as part of the
  initial client beta.

## Package Boundaries

The first monorepo iteration contains:

| Package | Responsibility | Runtime constraints |
| --- | --- | --- |
| `openfeature_dart_server_sdk` | Existing dynamic-context SDK | Server Dart; current API remains compatible |
| `openfeature_dart_client_sdk` | Static-context API, provider lifecycle, hooks, events, tracking, and evaluation | Pure Dart; web-compatible; no Flutter dependency |

Both publishable SDKs live under `packages/`. Repository safety must ensure:

- CI discovers, analyzes, and tests every package explicitly;
- `dart pub publish --dry-run` validates each package-specific archive;
- release and publish workflows route tags to the correct package directory.

The client publication command continues to stage only the client directory in
a temporary location before it runs `dart pub publish`. CI and tag publication
use the same staging command. The server package publishes directly from
`packages/openfeature_dart_server_sdk`.

Shared code should be extracted only when both packages require the same stable,
specification-neutral contract. Candidate types include flag values, provider
metadata, evaluation details, error codes, and event metadata. Server lifecycle,
transaction context, client context reconciliation, HTTP transports, and caches
must not be placed in a shared package merely to avoid small amounts of
duplication.

Do not create a public shared package in the first change. Start the client
package with an explicit contract inventory, then extract shared types in a
separate reviewed change when the compatibility benefit is demonstrated.

## Core and Provider Boundary

The client SDK defines the portable OpenFeature contract. It owns static
evaluation context, provider registration and binding, lifecycle coordination,
context reconciliation scheduling, typed evaluation methods, hooks, event
dispatch, tracking dispatch, defaults, errors, and conformance behavior.

Provider packages remain external to the core repository and own
vendor-specific transport, client-safe authentication, assignment retrieval,
cache persistence and invalidation, local evaluation details, and telemetry
mapping. Framework-specific integrations, including Flutter lifecycle or
observability adapters, remain optional layers over the pure Dart client
package.

An existing vendor SDK may implement the provider contract directly or be
wrapped by a thin OpenFeature provider. Its behavior must not become an
implicit requirement of the core SDK unless that behavior is accepted as part
of the provider-neutral public contract.

## Client Contract

The client SDK must provide:

- A default global API singleton that owns providers, domains, hooks, handlers,
  and static evaluation context.
- An intentionally separate factory or import path for isolated API instances,
  each with independent providers, context, hooks, handlers, and shutdown.
- Typed value and evaluation-details methods for boolean, string, integer,
  double, and structured values.
- Global and domain-scoped evaluation context.
- No client-level, invocation-level, or transaction evaluation-context setter.
- Optional provider initialization, shutdown, and context-change capabilities.
- Provider states `NOT_READY`, `READY`, `RECONCILING`, `STALE`, `ERROR`, and
  `FATAL` where applicable to the static-context paradigm.
- Provider-emitted readiness, error, stale, configuration, reconciliation, and
  context-changed events, with API and client handler registration.
- Hook execution and optional tracking without exposing provider internals.
- An in-memory provider suitable for conformance and application tests.

The client uses synchronous flag-evaluation methods. A provider resolver reads
only locally available state and must not perform network, file, or
platform-channel I/O during flag evaluation. This is a Dart client design
constraint, not a separate OpenFeature requirement. It makes synchronous
evaluation non-blocking and predictable in widget builds and other hot paths.

Provider initialization, context reconciliation, and shutdown are asynchronous
and return `Future<void>` when implemented. The API provides non-awaiting
mutators and awaitable variants:

- `setProvider` starts initialization and contains asynchronous failures;
  `setProviderAndWait` settles after initialization terminates and the resulting
  lifecycle event has updated status.
- `setEvaluationContext` schedules reconciliation and contains asynchronous
  failures; `setEvaluationContextAndWait` settles after the requested revision
  has been reconciled by all affected providers.
- Domain-scoped provider and context mutators follow the same naming and waiting
  semantics.

Non-awaiting mutators must not surface asynchronous failures as uncaught zone
errors. Awaitable variants may complete with an idiomatic lifecycle or
configuration error after the required status update has been processed.

Hooks used during flag evaluation are synchronous. Tracking is a non-blocking
`void` operation. Providers should flush relevant queued tracking work during
bounded asynchronous shutdown; any inability to flush must follow a documented
provider policy rather than silently weakening the core contract.

## Provider Lifecycle and Events

Providers are the source of lifecycle events in v0.9.0. The SDK listens for
provider events, updates provider status, and only then invokes associated API
and client handlers.

- A provider with `initialize` emits `PROVIDER_READY` before initialization
  terminates normally or `PROVIDER_ERROR` before it terminates abnormally.
- `PROVIDER_FATAL` is an error code on `PROVIDER_ERROR`, not an event. It maps
  provider status to `FATAL`.
- A provider without `initialize` is treated as `READY`, and the SDK runs ready
  handlers on its behalf.
- Shutdown is the lifecycle exception inferred by the SDK: status becomes
  `NOT_READY` after the provider's shutdown function terminates.
- `setProviderAndWait` waits for initialization termination and processing of
  its resulting lifecycle event; application event handlers need not finish
  before the call settles.

Provider status is observable state, not an SDK evaluation gate. A resolver is
responsible for reporting `PROVIDER_NOT_READY`, `PROVIDER_FATAL`, or another
error during abnormal resolution, after which the client returns the
application default and runs the required error/finally hooks.

## Context Reconciliation

Client context represents one user or session and changes less frequently than
server request context. The SDK distinguishes a requested context revision from
the active, fully reconciled revision. Evaluation uses only the active context
and provider state, so values associated with a previous targeting identity
cannot be exposed as belonging to a newly requested identity.

Context-change callbacks are serialized per provider. Different provider
instances may reconcile concurrently. Every requested mutation receives a
monotonically increasing revision and is processed in request order for each
affected provider:

1. Record the requested global or domain context revision.
2. Invoke each affected provider's `on context changed` callback with the
   previous active context and the requested context.
3. For asynchronous reconciliation, the provider emits
   `PROVIDER_RECONCILING`; the SDK updates status before running handlers.
4. On normal completion, the provider emits `PROVIDER_CONTEXT_CHANGED`. After
   the callback has terminated, the SDK marks that revision active before it
   dispatches the terminal event to handlers. Evaluations started by those
   handlers therefore use the announced revision.
5. On abnormal completion, the provider emits `PROVIDER_ERROR`, using the
   `PROVIDER_FATAL` error code only for an irrecoverable error.
6. The awaitable mutator for a revision settles after all providers affected by
   that revision have completed and the resulting events have been processed.

The SDK does not synthesize or suppress provider reconciliation events. Per-
provider serialization avoids reentrant terminal-event ambiguity while still
running the callback for every context mutation required by the specification.
A late result cannot replace state for a later active revision.

A context override for a domain without its own provider remains pending. While
that domain falls back to the default provider, evaluations use the global
context so the context passed to the resolver matches the default provider's
reconciled state. The pending domain override becomes active when a provider is
bound to that domain.

During `RECONCILING`, a resolver may return a value only when the provider can
prove that the value belongs to the active context; otherwise it reports an
error and the client returns the application default. `STALE` is not a direct
reconciliation result. A provider may independently emit `PROVIDER_STALE` when
its cache is no longer current.

Lifecycle status is tracked per provider instance, while provider and context
selection is tracked per domain binding. A provider instance is initialized
once per active lifecycle and shut down only after its final binding is
removed. After shutdown, that instance may begin a new lifecycle only when the
provider supports reinitialization; the SDK completes that initialization
before making a new binding active.

A provider declaring itself domain-scoped can be bound to at most one domain,
regardless of whether multiple domains currently have equal contexts. The SDK
rejects a second domain binding and leaves the first intact. The bound domain is
passed to initialization. A provider that does not reconcile cached context may
serve multiple domains because each resolver receives the selected context.
Until the provider contract has a domain-aware reconciliation callback, a
provider implementing `ContextReconciliationProvider` can have only one active
binding and must use separate instances for independently scoped contexts.

Initialization and reconciliation waits are bounded to 30 seconds by default.
An isolated API may configure a shorter timeout for tests. A provider that
returns without emitting the operation's terminal event fails within that
bound and cannot permanently block the serialized mutation queue or shutdown.
Because Dart futures cannot be cancelled, a timed-out provider is detached and
quarantined from reuse; late events are ignored and callers must supply a new
provider instance. Subscription cancellation and provider shutdown are bounded
by the same lifecycle timeout.

Tests cover sign-in, sign-out, account switching, queued rapid updates, refresh
failure, provider replacement, shutdown during reconciliation, and late work
from an older revision.

## Remote Evaluation and Authentication

The client SDK owns no vendor authentication scheme. Providers may use OFREP or
another vendor protocol, but distributed applications must not contain OAuth
client secrets, service credentials, or administrative API tokens.

A remote-evaluation provider should prefer the OFREP static-context flow:

1. Obtain a short-lived, client-safe credential from an application-controlled
   backend or an approved public-client authorization flow.
2. Submit the current static context to the bulk-evaluation endpoint.
3. Cache the returned flag set for local typed evaluation.
4. Use ETags or equivalent revisions for conditional refresh.
5. Clear or partition cached data whenever the targeting identity changes.
6. Apply an explicit stale-data policy and always preserve application defaults.

Credential refresh and flag refresh are separate concerns. A provider must not
silently convert server-side client-credentials authentication into a mobile or
browser integration.

## Repository Migration

The repository rename to `open-feature/dart-sdk` and relocation of both SDKs
under `packages/` are complete. The independently reviewed phases are:

1. **Architecture baseline:** this document records the package boundaries,
   naming, versioning, and v0.9.0 conformance gates.
2. **Package safety and CI (implemented):** per-package analysis/tests,
   publication dry runs, and release routing preserve existing server releases.
3. **Additive client beta (published):** `packages/openfeature_dart_client_sdk/`
   contains the client package; `0.0.1-beta.1` is published.
4. **Package alignment (complete):** the server package is under
   `packages/openfeature_dart_server_sdk/`, with its release history and tag
   format preserved. Git consumers must use the documented package path.
5. **Provider and platform validation:** exercise exact client commits or
   immutable prereleases across pure Dart web, Flutter consumers, and
   independently maintained providers.
6. **Stable client release:** publish `0.0.1` only after the conformance and
   release gates in this document pass.

The established server tag format remains `v0.0.x`; for example, its current
published release is `v0.0.24`. Client tags include the component to avoid ambiguity,
for example `openfeature_dart_client_sdk-v0.0.1-beta.1` and
`openfeature_dart_client_sdk-v0.0.1`.

The client package bootstrap is complete. Both packages are configured for
tag-bound OIDC publishing from `open-feature/dart-sdk`; see
[the client release guide](client-sdk-release.md) for the publication process.

The repository layout is:

```text
dart-sdk/
|-- doc/
|-- packages/
|   |-- openfeature_dart_server_sdk/
|   `-- openfeature_dart_client_sdk/
|-- test/                        # repository tooling tests
|-- tool/                        # repository tooling
`-- pubspec.yaml                # non-publishable repository tooling package
```

The completed repository rename and package relocation do not establish full
v0.9 conformance or satisfy the remaining stable-client release gates.

## Provider Validation

External providers should be developed after the client provider interface and
lifecycle skeleton are reviewable. They act as independent contract tests, not
as dependencies of the core SDK.

Each validation provider must demonstrate:

- Static-context reconciliation and identity-safe cache replacement.
- Boolean, string, numeric, and structured flag evaluation.
- Evaluation details, errors, reasons, variants, and metadata.
- Startup, refresh, degraded-network, tracking, and shutdown behavior.
- Browser and Flutter consumption without Flutter in its core dependency graph.
- Authentication that is safe for distributed clients.

Vendor-specific code, endpoints, credentials, and release ownership remain in
the provider's repository.

## Repository Workflow

The canonical OpenFeature repository uses public GitHub issues, short-lived
feature branches, and draft pull requests. During the client SDK beta,
architecture and implementation pull requests target `development`, which is
the integration and QA branch. It is not currently protected by a repository
ruleset. Adding protection is a separate governance change rather than a claim
made by this architecture.

No permanent client integration branch is introduced. Before merge, dependent
provider tests use the exact feature-branch commit. After merge, beta integration
uses an exact `development` commit or a published prerelease. Released provider
packages must not depend on a floating SDK branch.

The `main` branch remains the protected release line unless repository
governance deliberately changes the promotion policy.

## Ownership

- Existing Dart maintainers retain repository-wide architecture, shared
  contracts, server package, compatibility, and release governance.
- Client contributors may become component owners for the client package
  through the normal OpenFeature contributor process.
- Provider maintainers own vendor implementations and provider releases.
- Application maintainers own downstream product integration.

Component ownership does not transfer repository-wide governance.

## Delivery Sequence

1. Complete the client API matrix, mapping every applicable v0.9.0 requirement
   to a Dart API and conformance test.
2. Establish package-safe CI, archive boundaries, version routing, and release
   dry runs without changing the published server package identity.
3. Land the client package scaffold, provider contract, lifecycle coordinator,
   typed evaluation, hooks, events, tracking, and in-memory provider through
   small reviewable pull requests.
4. Build pure Dart providers in their respective repositories as independent
   validation of the client interface.
5. Test the core on Dart VM and web and as a dependency of Flutter targets.
   Flutter pause/resume and platform lifecycle behavior belongs to provider or
   adapter integration tests, not pure-Dart core conformance.
6. Exercise independent package validation, changelogs, tagging, and publishing
   before the first client prerelease.

## Version Sequence

The client package begins independently from the existing server package:

```text
0.0.1-beta.1
0.0.1-beta.2
0.0.1-rc.1       # optional
0.0.1            # first stable client release
0.0.2            # subsequent compatible release
```

The server remains on its existing independent `0.0.x` sequence.

## Release Gates

The client package is not ready for its first stable release until:

- Every applicable v0.9.0 MUST requirement has requirement-indexed tests or an
  explicit language/paradigm rationale.
- Browser builds contain no `dart:io`, Flutter, or platform-channel dependency.
- Context changes cannot leak cached flags across targeting identities.
- Defaults are returned predictably during provider failure.
- No distributed-client example embeds a server credential.
- Independent versioning, archive validation, tagging, and publishing are
  exercised from the correct package directory.
- At least two independently maintained providers pass the same contract tests
  against an immutable client version.

## References

- [OpenFeature v0.9.0](https://github.com/open-feature/spec/releases/tag/v0.9.0)
- [OpenFeature SDK paradigms](https://openfeature.dev/docs/reference/concepts/sdk-paradigms/)
- [OpenFeature v0.9.0 flag evaluation](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/01-flag-evaluation.md)
- [OpenFeature v0.9.0 providers](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/02-providers.md)
- [OpenFeature v0.9.0 evaluation context](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/03-evaluation-context.md)
- [OpenFeature v0.9.0 events](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/05-events.md)
- [OpenFeature Remote Evaluation Protocol](https://openfeature.dev/docs/reference/other-technologies/ofrep/)
- [Dart package layout conventions](https://dart.dev/tools/pub/package-layout)
- [Dart Pub workspaces](https://dart.dev/tools/pub/workspaces)
- [Automated publishing to pub.dev](https://dart.dev/tools/pub/automated-publishing)
