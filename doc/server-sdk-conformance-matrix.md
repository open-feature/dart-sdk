# Dart server SDK OpenFeature v0.9 conformance matrix

Status: maintainer proposal
Tracks: [#121](https://github.com/open-feature/dart-sdk/issues/121)
Specification baseline: [OpenFeature v0.9.0](https://github.com/open-feature/spec/releases/tag/v0.9.0)
Implementation baseline: lifecycle work proposed in #131

## Purpose and scope

This document maps the existing `openfeature_dart_server_sdk` package to the
OpenFeature v0.9 contract. It is an implementation plan and review aid, not a
claim of conformance.

The server SDK continues to use the dynamic-context paradigm. Flag evaluation
remains asynchronous, and API, transaction, client, invocation, and before-hook
contexts participate in evaluation. Static-context reconciliation belongs to
the separately proposed client SDK in #117 and is not imported into this
package.

The conformance work must preserve:

- the `openfeature_dart_server_sdk` package name and existing import paths;
- pure Dart operation with no Flutter dependencies;
- asynchronous server-side evaluation;
- invocation-scoped dynamic context;
- public compatibility through adapters and deprecations where practical.

The repository is now `open-feature/dart-sdk`, and both SDKs use the
`packages/` layout. Those migration changes are complete and independent of
the remaining v0.9 behavioral implementation.

## Legend

| Mark | Meaning |
| --- | --- |
| Conformant | Implemented with relevant evidence; requirement-indexed tests may still be needed. |
| Partial | Partially represented, but the current behavior or public contract is not conformant. |
| Missing | Missing or materially incompatible. |
| N/A | Not applicable to the dynamic-context server paradigm. |

## P0: lifecycle and evaluation safety

These corrections establish safe provider replacement and deterministic
evaluation behavior before wider API cleanup.

| Area | v0.9 requirements | Current state and evidence | Required correction | Test gate | Compatibility approach |
| --- | --- | --- | --- | --- | --- |
| Provider-owned lifecycle events | 1.1.2.4; 1.7.1-1.7.6; 2.8.1-2.8.5; 5.3.1-5.3.3 | Partial: new initialization capabilities require provider-owned ready/error events before termination, including normal asynchronous stream delivery. Resolver-only providers are ready without initialization events. Legacy eventful FeatureProvider implementations alone retain the one-second migration grace. | Retire the legacy grace only after provider migration; complete the requirement report in #165; the canonical event API is covered by #162. | provider_capabilities_test.dart covers event timing, missing/contradictory events, status-before-handler and resolver-only readiness. Existing provider_lifecycle_test.dart legacy grace and lifecycle tests pass. | ProviderInitialization couples initialization and event support. LegacyProviderLifecycleAdapter names the legacy-only synthesized-event and delivery-grace policy. |
| Provider status | 1.7.1-1.7.6; 2.8; 5.1.4-5.1.5 | Conformant for P0: status is maintained per provider instance, exposed on bound clients, updated before associated handlers, and normalized to `NOT_READY` after shutdown. `NOT_READY` and `FATAL` evaluations now short-circuit with their specified errors. | Reconcile the expanded legacy `ProviderState` enum with the five public v0.9 states during P1 API cleanup. | Passing status-transition, handler-observed status, shutdown, `NOT_READY`, and `FATAL` short-circuit tests. | Preserve legacy names internally while exposing one canonical public status contract. |
| Instance-aware provider binding | 1.1.2.1-1.1.2.3; 1.1.3; 1.1.8.1; 1.8.4 | Conformant for P0: the lifecycle manager tracks object identity independently from metadata name, reference-counts bindings, isolates same-name instances, and shuts a provider down only after its final binding is removed. Latest concurrent requests win, failed domain requests restore the prior pending binding, and domain-scoped providers reject a second domain. | Carry the focused replacement-race/concurrency evidence into the requirement-indexed P2 suite. | Passing same-name isolation, final-binding shutdown, concurrent default/domain replacement, failed-request rollback, legacy name-first activation, and domain-scoped rejection tests. | Provider names remain metadata; explicit provider IDs supply registry identity without removing legacy name-first binding yet. |
| Dynamic client rebinding | 1.1.3; 1.1.6-1.1.8; 1.2.2; 5.1.2-5.1.3 | Partial: existing clients resolve current default/domain providers and status dynamically. Immutable domain metadata now preserves the requested binding through fallback and replacement; metadata attributes are defensively copied. Typed handlers now follow provider identity and domain, including default fallback and pending replacement. | Complete the remaining client-creation contract and requirement-indexed report in #165. | `required_defaults_test.dart` covers requested domain across default fallback/replacement and explicit domain binding; `evaluation_foundations_test.dart` covers immutable attributes. `typed_events_test.dart` covers typed readiness, errors and binding isolation; existing replacement/race tests remain passing. | Existing name-based factory remains; explicit domain takes precedence for metadata.domain while legacy metadata.name is retained. |
| Evaluation defaults and failure contract | 1.3.1.1-1.3.4; 1.4.1.1-1.4.15.1; 2.2.1-2.2.10 | Partial: new `get*Value` / `get*EvaluationDetails` methods require application defaults for all five types. Provider-reported errors normalize to the application default; required-default methods contain provider lookup and evaluation failures. Legacy optional-default methods remain during migration. | Evaluation options remain #161; provider-surface and complete requirement-indexed gates remain #160/#165. This row is not a full v0.9 conformance claim. | `required_defaults_test.dart`: five types, value/details, general/type-mismatch/thrown errors, NOT_READY/FATAL, failed provider resolution and all-ten-method negative/legacy analyzer fixtures. `evaluation_foundations_test.dart`: previously failing remote-error fallback reproduction. | Additive methods; staged deprecation/removal requires separate maintainer review. See `packages/openfeature_dart_server_sdk/doc/evaluation-defaults-migration.md`. |
| Evaluation context | 3.1.1-3.1.4; 3.2.1.1; 3.2.3 | Partial: explicit `EvaluationContext.immutable`, `.snapshot()` and `setEvaluationContext` capture nested fields, parents and rules. Legacy APIs retain their prior value/collection behavior; they do not enforce deep immutability. Both paths preserve complete parent fields and local targeting-key precedence. | Review a versioned migration before imposing strict validation or collection normalization on legacy APIs. Propagator lifecycle and complete hooks remain separate work. | `context_review_regression_test.dart` covers legacy value, provider and targeting compatibility; `context_contract_test.dart` covers opt-in snapshots and five context levels. | Keep the const constructor and positional-map adapter. See the package context migration guide for opt-in validation, collection normalization and legacy aliasing. |

## P1: complete the public contract

| Area | v0.9 requirements | Current state and evidence | Required correction | Test gate | Compatibility approach |
| --- | --- | --- | --- | --- | --- |
| Provider surface | 2.1.1; 2.2; 2.3; 2.4; 2.5; 2.7 | Implemented additively: Provider requires metadata and typed resolvers only. Initialization, shutdown, hooks and tracking are separate capabilities; initial global context and first domain are captured. Legacy FeatureProvider objects retain source compatibility and identity. | Review the capability naming/legacy policy in #160. Complete hook/options contracts (#161), API shutdown (#163), tracking details/nonblocking API (#164) and final evidence (#165). | provider_capabilities_test.dart: minimal implements-only provider, optional capabilities, context/domain, concurrent first binding, domain-scoped enforcement, strict lifecycle events, shutdown-once, hooks/tracking and legacy compatibility. Existing replacement-race tests pass. | API registration accepts Provider and caches an internal bridge per identity. Existing FeatureProvider and its old methods remain; see provider-capabilities-migration.md. |
| Hooks and evaluation options | 1.5.1; 2.3.1-2.3.3; 4.1-4.6 | Implemented for the dynamic-context hook slice: immutable invocation options/hints; typed supported stages; API/client/invocation/provider registration snapshots; insertion before and reverse cleanup; mutable identity-isolated hook data; opt-in typed-hook input snapshots; exact-default/error/finally details. Legacy hook value behavior is retained. | Review the additive typed-hook snapshot opt-in, invalid-input diagnostic behavior and priority compatibility decision in #161; complete API reset/independent-instance hook isolation in #163 and final conformance report in #165. | `hooks_regression_test.dart` reproduces late API registration, priority inversion and stale finally details. `hook_contract_test.dart` covers all four scopes, twenty evaluation methods, data lifetime/concurrency, merge/immutability, per-type failures, timeout and remaining cleanup. `hook_legacy_compatibility_test.dart` covers preserved opaque/typed/cyclic legacy values, after-only capture and cleanup after invalid snapshots. | Existing Hook/BaseHook/OpenFeatureHook signatures remain. New EvaluationHook callbacks provide typed stage arguments and finallyAfter; SDK ignores priority, while direct standalone HookManager retains its old priority behavior. See hooks-migration.md. |
| Event API and isolation | 5.1.1-5.1.5; 5.2.1-5.2.7; 5.3.1-5.3.5 | Implemented event slice: canonical lifecycle model, typed API/client registration and removal, immediate state delivery, identity/domain routing, failure containment and compatible streams share one dispatcher. | Retain legacy lifecycle grace pending provider migration; complete the requirement report in #165. Static-context reconciliation requirements remain N/A for this server. | `typed_events_test.dart`: 17 requirement-indexed cases for typed registration/removal, same-name/domain isolation, default fallback/replacement, late/reentrant handlers, metadata, failure containment and status ordering. Existing lifecycle/capability race suites remain required. | Lifecycle enum/constructor compatibility adapters and existing streams use the canonical dispatcher. Standalone application telemetry utilities in `event_system.dart` are deprecated, not an SDK provider bus. See `packages/openfeature_dart_server_sdk/doc/events-migration.md`. |
| API shutdown and reset | 1.6.1-1.6.2; 1.7.6; 2.5 | Implemented reusable shutdown: all tracked providers receive cleanup once per lifecycle, API-owned state is cleared, old initialization/binding generations cannot restore state, and clients resolve a fresh initial provider. Permanent disposal also cleans providers. | Complete the full conformance report in #165. Providers must abort their own startup; SDK ownership remains reserved until outstanding initialization settles. | `api_shutdown_isolation_test.dart`: shutdown-once/uninitialized registrations, failure resilience, paused streams, late initialization/events, transaction invalidation, reuse and concurrent disposal. Existing lifecycle race tests remain required. | `shutdownProvider` remains focused; `resetInstance` now surfaces provider cleanup failures after releasing the singleton. See `doc/shutdown-and-isolation.md` in the server package. |
| Independent API instances | 1.8.1-1.8.4 (experimental) | Implemented `experimental/isolated.dart` factory with independent providers, context, hooks, events, transaction managers and cleanup. The ordinary constructor remains the singleton. Provider identity ownership rejects cross-instance reuse until the prior association and pending initialization are retired. | Keep experimental maturity and complete the broader requirement report in #165. | `api_shutdown_isolation_test.dart`: singleton/peer isolation, provider ownership/adapter identity, release/reuse, transaction zones, cleanup and unchanged process logging configuration. | Separate opt-in import; internal annotated constructor only bridges the factory. Provider reinitialization support remains provider-owned. |
| Tracking | 2.7.1; 6.1.1.1-6.1.4; 6.2.1-6.2.2 | Partial: client and provider tracking exist, but every provider must implement it; tracking value is `double?` rather than `num?`; context integrity and custom detail types are not fully enforced. | Make tracking a provider capability, merge the conformant context, accept the specified numeric value shape, validate allowed custom fields, and define behavior for providers without tracking support. | Tracking/no-tracking provider, context merge, targeting-key, integer/double value, custom-field type, and shutdown/flush tests. | Supply a legacy tracking adapter and deprecate the mandatory provider method. |
| Transaction context | 3.3.1.1-3.3.2.1 (experimental) | Partial: a transaction context manager exists, but it needs requirement-indexed evidence, explicit propagator lifecycle, and isolation validation. | Verify idiomatic async-zone propagation, API registration/removal, merge precedence, and reset on shutdown. Document experimental status. | Nested async zone, concurrent request isolation, precedence, missing propagator, and shutdown reset tests. | Preserve existing transaction APIs when their behavior is conformant; adapt names separately from semantics. |

## P2: conformance and migration evidence

| Deliverable | Required result | Merge gate |
| --- | --- | --- |
| Requirement-indexed test suite | Each applicable v0.9 MUST has a passing test or a documented language/paradigm exception. SHOULD requirements have tests or recorded rationale. | CI publishes a matrix report tied to the v0.9 requirement identifiers. |
| Public API migration guide | Provider authors and SDK users can identify replacements, adapters, deprecations, and removal targets. | Examples cover provider events, provider replacement, contexts, hooks, events, tracking, and shutdown. |
| Package compatibility check | Existing package/import identity remains usable throughout the conformance stream. | A fixture using the last pre-conformance public API compiles against the compatibility layer. |
| External provider validation | At least one server provider passes lifecycle, evaluation, hook/event, and tracking integration scenarios without vendor logic entering core. | Validation runs in the provider's canonical repository and records the exact SDK prerelease/commit. A read-only mirror is not used as release or CI authority. |
| Documentation accuracy | README and API docs stop claiming v0.8 once the v0.9 gates pass and do not claim conformance earlier. | Published conformance statement links the tested matrix and specification release. |

## Explicitly non-applicable static-context requirements

The server package uses dynamic invocation context. The following v0.9
requirements are therefore not implementation targets for this package:

- 3.2.2.1-3.2.2.4: static-context API/domain context management;
- 3.2.4.1-3.2.4.2: automatic provider reconciliation after static context
  mutation;
- lifecycle behavior that exists only to reconcile a client-side evaluated flag
  cache after a static identity change.

The optional provider `on context changed` capability in 2.6.1 may still be
represented by a shared provider abstraction, but the dynamic server API must
not invoke it as a substitute for passing merged invocation context to every
evaluation.

## Implementation sequence

1. Land this matrix and agree on the legacy-provider compatibility boundary.
2. Complete: add focused lifecycle/status tests, provider events, and the
   instance-aware binding coordinator.
3. In progress: finish client metadata, required evaluation defaults, and the
   canonical immutable context model. The current provider-rebinding race suite
   passes, but complete requirement-indexed evaluation evidence remains open.
4. Normalize hooks, events, tracking, shutdown, and independent API instances.
5. Add the complete requirement-indexed suite and migration guide.
6. Publish a server SDK prerelease for external provider validation.
7. Preserve the completed package relocation and repository rename as the
   baseline; they do not imply completion of the conformance work above.

Each implementation PR should reference #121, identify the matrix rows it
closes, and avoid mixing client-SDK or repository-migration changes into the
server conformance diff.
