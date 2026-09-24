# Dart Client SDK OpenFeature v0.9 Conformance Matrix

## Purpose

This matrix converts the applicable OpenFeature v0.9.0 static-context
requirements into the initial Dart client SDK implementation and test backlog.
It is a planning and review aid, not a claim that the package is already
conformant.

Requirement identifiers refer to the immutable
[OpenFeature v0.9.0 release](https://github.com/open-feature/spec/releases/tag/v0.9.0).
A later specification is adopted only through an explicit gap analysis and
matrix update.

## Target

- Package: `openfeature_dart_client_sdk`
- Paradigm: static context
- Initial platforms: Dart VM, Dart web, and consumption from Flutter targets
- Specification baseline: OpenFeature v0.9.0
- Initial prerelease: `0.0.1-beta.1`
- First stable release: `0.0.1`
- Status: initial beta contract implemented; full conformance is in progress

## Maturity Legend

| Maturity | Meaning in v0.9.0 |
| --- | --- |
| Stable | Breaking changes require a major specification release. |
| Hardening | Suitable for production feedback, but a minor specification release may still make consensus-approved breaking changes. |
| Experimental | Under active development; breaking changes may occur in a minor specification release. |
| Project gate | A Dart SDK quality constraint that is deliberately stronger than, or additional to, a normative requirement. |

Implementing an experimental requirement does not make that feature stable.
Public documentation and annotations must preserve the specification's maturity
signal.

## Conformance Areas

| Area | Maturity | Normative reference | Proposed Dart surface | Required first tests |
| --- | --- | --- | --- | --- |
| Default API and clients | Stable | Requirements 1.1.1, 1.1.5 through 1.1.7, and 1.2.2 | `OpenFeatureAPI.instance`, `getClient`, immutable client domain metadata, and provider metadata access | Default singleton behavior; client creation never throws; domain metadata is immutable; default-provider fallback works |
| Provider registration and domains | Stable/Hardening | Requirements 1.1.2.1 through 1.1.2.4, 1.1.3, and conditional requirement 1.1.8.1 | Default and domain provider mutators with `AndWait` variants | Initialize once; wait for lifecycle event processing; overwrite a binding; final-binding shutdown; domain-scoped second binding is rejected and first binding remains intact |
| API shutdown and reset | Hardening | Requirements 1.6.1 and 1.6.2 | `Future<void> shutdown()` | Every registered provider shuts down once; providers, hooks, handlers, context, and propagators reset; API is reusable with a no-op provider |
| Provider status | Hardening | Requirements 1.7.1 through 1.7.6, including conditional requirement 1.7.2.1 | `ProviderStatus` and client status accessor | `NOT_READY`, `READY`, `RECONCILING`, `STALE`, `ERROR`, and `FATAL`; status updates before handlers; shutdown becomes `NOT_READY` |
| Isolated API instances | Experimental | Requirements 1.8.1 through 1.8.4 | Factory exposed from a deliberate secondary library/import path | Providers, context, hooks, events, clients, and shutdown are isolated from the singleton and other instances; warn or reject simultaneous cross-instance provider reuse |
| Typed evaluation | Hardening | Conditional requirements 1.3.2.1, 1.3.3.1, 1.4.2.1; requirements 1.3.4 and 1.4.3 through 1.4.15.1 | Synchronous boolean, string, integer, double, and structured value/details methods with required defaults and optional evaluation options; non-null immutable `flagMetadata` with an empty record when omitted by the provider | Correct types; default on abnormal execution; no escaping exception; details preserve key, value, reason, variant, and error; provider omission produces empty `flagMetadata`; mutation throws `UnsupportedError` |
| Evaluation options | Stable | Requirement 1.5.1 | Immutable evaluation options carrying invocation hooks and hints | Invocation hooks join the required order without adding invocation context; hints are immutable |
| Provider resolution | Stable | Requirements 2.2.1 through 2.2.10 | Synchronous typed resolver methods returning `ResolutionDetails<T>` | Current active static context reaches provider; normal and abnormal result shapes; provider reports `PROVIDER_NOT_READY` and `PROVIDER_FATAL`; SDK status alone does not skip resolution |
| Provider metadata and hooks | Stable | Requirements 2.1.1, 2.2.10, and 2.3.1 through 2.3.3 | Immutable `ProviderMetadata`, immutable flag metadata, optional provider hooks | Metadata survives evaluation; invalid metadata values rejected; provider hooks join lifecycle order; normal results omit error details |
| Provider lifecycle and scope | Hardening | Requirements 2.4.1, conditional requirement 2.4.2.1, requirements 2.4.3, 2.4.4, and 2.5.1 through 2.5.3 | Optional asynchronous `initialize`, `shutdown`, and a `DomainScopedProvider` capability | Initial global context and optional first-bound domain supplied; abnormal initialization; repeated shutdown; reinitialization where supported; domain-scoped contract |
| Provider-owned status events | Hardening | Requirements 2.8.1 through 2.8.4 and conditional requirement 2.8.5.1 | Provider event source plus SDK status/event coordinator | Provider emits ready/error before initialization terminates; provider emits reconciliation outcomes; SDK synthesizes only ready for a provider without initialization and infers only shutdown `NOT_READY` |
| Context reconciliation callback | Hardening | Requirement 2.6.1 | Optional asynchronous `onContextChanged(previous, current)` | Previous and requested contexts supplied; callback runs for every applicable mutation; no call for an unaffected provider |
| Evaluation context values | Hardening | Requirements 3.1.1 through 3.1.4 | Immutable `EvaluationContext` with targeting key and typed attributes | Targeting key; boolean, string, number, datetime, and structure values; unique keys; keyed and complete-map access; deep immutability |
| Global static context | Hardening | Conditional requirement 3.2.2.1 | Global `setEvaluationContext` and `setEvaluationContextAndWait` | Non-awaiting failures are contained; awaited revision completes after all affected providers process its lifecycle outcome |
| No client, invocation, or transaction context | Hardening/Experimental | Conditional requirements 3.2.2.2 and 3.3.2.1 | Evaluation methods omit context parameters; no transaction-context propagator API | Compile-time public API has no client/invocation context setter or evaluation parameter and no transaction propagator |
| Domain context | Hardening | Conditional requirements 3.2.2.3 and 3.2.2.4 | Domain set, clear, and corresponding `AndWait` mutators | Domain override; global fallback; unbound overrides remain pending until a domain provider is bound; clear; binding isolation; non-domain-scoped provider sharing; domain-scoped second binding rejection |
| Context change dispatch | Hardening | Conditional requirements 3.2.4.1 and 3.2.4.2 | Internal reconciliation scheduler | A global mutation reaches all providers using global context; a domain mutation reaches only its associated provider |
| Ordered reconciliation | Hardening/Project gate | Conditional requirements 5.3.4.1 through 5.3.4.3 | Requested and active revisions with a serialized queue per provider | Every mutation runs; active identity never moves backward; each awaited revision has per-call completion; providers can reconcile concurrently with one another but not reentrantly with themselves |
| Hook context and hints | Hardening | Requirements 4.1.1 through 4.1.5 and 4.2.1 through 4.2.2.3 | Immutable invocation fields and hints, mutable per-hook data | Required fields and metadata; hook-data isolation and propagation; immutable context, hints, client metadata, and provider metadata |
| Hook stages and order | Hardening | Requirements 1.1.4, 1.2.1, 4.3.1, 4.3.2, conditional requirement 4.3.3.1, requirements 4.3.6 through 4.3.8, and 4.4.1 through 4.4.7 | API, client, invocation-option, and provider hooks | Static `before` has no return value; before order API/client/invocation/provider; after/error/finally reverse order; hook failures and remaining-stage behavior conform |
| Provider events | Hardening | Requirements 5.1.1 through 5.1.5 | Provider event stream with ready, error, configuration-changed, stale, reconciling, and context-changed events | Associated API/client handlers only; `PROVIDER_FATAL` remains an error code, not an event; details include appropriate error data |
| Event handlers | Hardening | Requirements 5.2.1 through 5.2.7 | Typed API/client registration and removal | Details include provider name; one failing handler does not block others; handlers survive provider changes; removal works |
| Initialization events | Hardening | Requirements 5.3.1 through 5.3.3 | Provider-emitted ready/error events and immediate late-handler execution | Status updates before handlers; ready/error emitted before initialize terminates; event delivery is processed before `AndWait` settles; late handler runs immediately for current state |
| Reconciliation events | Hardening | Conditional requirements 5.3.4.1 through 5.3.4.3 and requirement 5.3.5 | Provider-emitted reconciling, context-changed, and error events | Async reconciliation announces `RECONCILING`; terminal event reflects the callback outcome; successful context is active before terminal handlers run; SDK updates status before handlers and neither synthesizes nor suppresses provider events |
| Tracking | Experimental | Condition 2.7.1, conditional requirement 6.1.2.1, and requirements 6.1.3, 6.1.4, 6.2.1, and 6.2.2 | Non-blocking `void track(name, details)` using active static context | Provider receives current context and typed details; unsupported tracking no-ops; call does not await I/O; bounded shutdown follows documented flush policy |
| In-memory provider | Project gate | Included Utilities, Appendix A | Public testing provider | Predefined typed flags; context callbacks; flag-set replacement emits configuration-changed with the union of old and new keys |
| End-to-end suite | Project gate | Included Utilities, Appendix A and Appendix B | Self-contained conformance fixture using the in-memory provider | Applicable official Gherkin scenarios run without a vendor service or credentials |

## Client-Specific Race and Safety Tests

These tests are release blockers even where the implementation mechanism is a
Dart project gate rather than a single normative requirement:

1. Anonymous -> user A -> user B changes cannot expose user A values after user
   B becomes active.
2. Sign-out prevents identity-specific values from being served as anonymous
   values.
3. Rapid context mutations run in request order per provider, and each awaited
   call settles for its own revision after the associated event is processed.
4. Different providers may reconcile concurrently without sharing revision or
   completion state.
5. Provider replacement during reconciliation cannot mutate the replacement
   provider's state or binding.
6. Shutdown during reconciliation prevents late work from restoring a provider
   or context after shutdown.
7. A resolver in `NOT_READY` or `FATAL` reports the corresponding provider
   error; the client returns the default and runs error/finally hooks without
   treating SDK-held status as a reason to skip the resolver.
8. A provider emits lifecycle events; the SDK updates status before handlers and
   does not synthesize or suppress reconciliation outcomes.
9. A domain-scoped provider rejects every second distinct domain even when the
   two domain contexts are equal, while a non-domain-scoped provider can be
   shared.
10. Late completion from an older revision cannot replace the active context or
    cached values belonging to a newer revision.
11. Evaluation details always expose non-null flag metadata; provider omission
    yields an empty record, and mutation throws `UnsupportedError` as the Dart
    enforcement of requirements 1.4.14 and 1.4.15.1.

## Platform Matrix

| Platform | Core compile gate | Core runtime gate | Integration ownership |
| --- | --- | --- | --- |
| Dart VM | `dart analyze` and tests | Lifecycle, hooks, events, tracking, and in-memory conformance | Core SDK |
| Dart web | `dart compile js` or browser test | No `dart:io`; reconciliation and events in a browser runtime | Core SDK |
| Flutter Android | Example build and focused tests | Pure-Dart core evaluation and lifecycle smoke | Core consumer example; app lifecycle belongs to provider/adapter tests |
| Flutter iOS | Example build and focused tests | Pure-Dart core evaluation and lifecycle smoke | Core consumer example; app lifecycle belongs to provider/adapter tests |
| Flutter web | Example build and browser test | Same client package as pure Dart web; no conditional Flutter API | Core consumer example |
| Flutter desktop | Representative example builds | Initialization and shutdown smoke | Core consumer example; platform resources belong to provider/adapter tests |

The core package must not import Flutter. Pause/resume, background execution,
platform channels, persistent caches, and network-transition behavior are tested
by the provider or optional Flutter adapter that owns those concerns.

## Package and Release Prerequisites

Before the client package directory can reach `main`:

- both publishable SDKs live under `packages/`;
- CI discovers and validates both packages plus repository tooling;
- each package passes analysis, tests, and a package-specific
  `dart pub publish --dry-run` archive check;
- existing server tags remain in the `v0.0.x` format;
- client tags use `openfeature_dart_client_sdk-v<version>`;
- release branch validation accepts both known Release Please components;
- tag routing publishes from the package that owns the tagged version; and
- the first client publication has a documented manual bootstrap before OIDC
  automation is enabled for subsequent releases.

## First Client Implementation Scope

After package-safety prerequisites are in place, the first client implementation
merge should contain only:

- Package scaffold, changelog, package documentation, and public library entry
  point.
- Flag values, evaluation context, metadata, resolution details, and errors.
- Client provider interface, provider status, event source, and optional
  lifecycle capability signatures.
- API/client method signatures for static context and typed evaluation.
- In-memory provider contract skeleton.
- Unit tests proving the public static-context shape, especially the absence of
  client, invocation, and transaction context.

It should not include an HTTP transport, OFREP provider, vendor provider,
Flutter dependency, persistent cache, server relocation, or repository rename.

## Candidate Work Split

| Workstream | Candidate lead | Review requirement |
| --- | --- | --- |
| Public API and specification mapping | OpenFeature Dart maintainers | Requirement-indexed maintainer review |
| Package safety, CI, and releases | OpenFeature Dart maintainers | Server archive and release regression evidence |
| Client lifecycle and context coordinator | Client-package contributors | Existing Dart maintainer approval and race tests |
| Events, hooks, tracking, and in-memory provider | Shared implementation | Conformance tests required |
| Independent remote providers | Independent provider maintainers | Kept outside core; shared contract suite passes for at least two providers before stable release |
| Pure Dart and Flutter consumption | Client-package contributors and provider maintainers | Core remains Flutter-free; provider/adapter owns platform lifecycle |

## Completion Rule

The proposed [shared provider contract and receipt process](client-provider-validation.md)
supplements the SDK suites. Reference VM/Chrome passes validate the harness only;
the two-independent-provider gate remains pending canonical provider receipts.

An item is complete only when its public API, normative behavior, abnormal
behavior, race behavior, and platform constraints are covered by automated
tests. Every applicable v0.9.0 MUST has a passing requirement-indexed test or an
explicit language/paradigm rationale. SHOULD requirements have tests or a
recorded rationale. A code path demonstrated only by one reference provider is
not core SDK conformance.

## References

- [OpenFeature v0.9.0 release](https://github.com/open-feature/spec/releases/tag/v0.9.0)
- [Flag Evaluation API v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/01-flag-evaluation.md)
- [Providers v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/02-providers.md)
- [Evaluation Context v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/03-evaluation-context.md)
- [Hooks v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/04-hooks.md)
- [Events v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/05-events.md)
- [Tracking v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/06-tracking.md)
- [Included Utilities v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/appendix-a-included-utilities.md)
- [Gherkin Suites v0.9.0](https://github.com/open-feature/spec/blob/v0.9.0/specification/appendix-b-gherkin-suites.md)
- [Dart package layout conventions](https://dart.dev/tools/pub/package-layout)
- [Dart Pub workspaces](https://dart.dev/tools/pub/workspaces)
- [Publishing Dart packages](https://dart.dev/tools/pub/publishing)
