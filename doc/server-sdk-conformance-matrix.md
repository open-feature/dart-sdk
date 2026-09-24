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
| Provider-owned lifecycle events | 1.1.2.4; 1.7.1-1.7.6; 2.8.1-2.8.5; 5.3.1-5.3.3 | Partial: `ProviderEventSource` supplies provider-owned events, status changes precede handlers, and legacy providers retain documented synthesized-event compatibility. The SDK temporarily tolerates late delivery after `initialize` as a migration aid, although v0.9 requires emission before termination. | Remove the late-event compatibility grace after provider migration and complete requirement-indexed coverage when the canonical event API is normalized in P1. | Passing event-before-return, bounded migration-tolerance, abnormal initialization, fatal error, already-ready provider, and legacy-adapter tests in `provider_lifecycle_test.dart`. | Keep the additive provider event interface and documented legacy adapter until the provider migration window closes. |
| Provider status | 1.7.1-1.7.6; 2.8; 5.1.4-5.1.5 | Conformant for P0: status is maintained per provider instance, exposed on bound clients, updated before associated handlers, and normalized to `NOT_READY` after shutdown. `NOT_READY` and `FATAL` evaluations now short-circuit with their specified errors. | Reconcile the expanded legacy `ProviderState` enum with the five public v0.9 states during P1 API cleanup. | Passing status-transition, handler-observed status, shutdown, `NOT_READY`, and `FATAL` short-circuit tests. | Preserve legacy names internally while exposing one canonical public status contract. |
| Instance-aware provider binding | 1.1.2.1-1.1.2.3; 1.1.3; 1.1.8.1; 1.8.4 | Conformant for P0: the lifecycle manager tracks object identity independently from metadata name, reference-counts bindings, isolates same-name instances, and shuts a provider down only after its final binding is removed. Latest concurrent requests win, failed domain requests restore the prior pending binding, and domain-scoped providers reject a second domain. | Carry the focused replacement-race/concurrency evidence into the requirement-indexed P2 suite. | Passing same-name isolation, final-binding shutdown, concurrent default/domain replacement, failed-request rollback, legacy name-first activation, and domain-scoped rejection tests. | Provider names remain metadata; explicit provider IDs supply registry identity without removing legacy name-first binding yet. |
| Dynamic client rebinding | 1.1.3; 1.1.6-1.1.8; 1.2.2; 5.1.2-5.1.3 | Partial: existing clients resolve current default/domain providers and status dynamically. Immutable domain metadata now preserves the requested binding through fallback and replacement; metadata attributes are defensively copied. Typed event registration remains open. | Finish typed, dynamically isolated client events in #162 and the remaining client-creation contract. | `required_defaults_test.dart` covers requested domain across default fallback/replacement and explicit domain binding; `evaluation_foundations_test.dart` covers immutable attributes. Existing replacement/race tests remain passing. | Existing name-based factory remains; explicit domain takes precedence for metadata.domain while legacy metadata.name is retained. |
| Evaluation defaults and failure contract | 1.3.1.1-1.3.4; 1.4.1.1-1.4.15.1; 2.2.1-2.2.10 | Partial: new `get*Value` / `get*EvaluationDetails` methods require application defaults for all five types. Provider-reported errors normalize to the application default; required-default methods contain provider lookup and evaluation failures. Legacy optional-default methods remain during migration. | Evaluation options remain #161; provider-surface and complete requirement-indexed gates remain #160/#165. This row is not a full v0.9 conformance claim. | `required_defaults_test.dart`: five types, value/details, general/type-mismatch/thrown errors, NOT_READY/FATAL, failed provider resolution and all-ten-method negative/legacy analyzer fixtures. `evaluation_foundations_test.dart`: previously failing remote-error fallback reproduction. | Additive methods; staged deprecation/removal requires separate maintainer review. See `packages/openfeature_dart_server_sdk/doc/evaluation-defaults-migration.md`. |
| Evaluation context | 3.1.1-3.1.4; 3.2.1.1; 3.2.3 | Partial: explicit `EvaluationContext.immutable`, `.snapshot()` and `setEvaluationContext` capture nested fields, parents and rules. Legacy APIs retain their prior value/collection behavior; they do not enforce deep immutability. Both paths preserve complete parent fields and local targeting-key precedence. | Review a versioned migration before imposing strict validation or collection normalization on legacy APIs. Propagator lifecycle and complete hooks remain separate work. | `context_review_regression_test.dart` covers legacy value, provider and targeting compatibility; `context_contract_test.dart` covers opt-in snapshots and five context levels. | Keep the const constructor and positional-map adapter. See the package context migration guide for opt-in validation, collection normalization and legacy aliasing. |

## P1: complete the public contract

| Area | v0.9 requirements | Current state and evidence | Required correction | Test gate | Compatibility approach |
| --- | --- | --- | --- | --- | --- |
| Provider surface | 2.1.1; 2.2; 2.3; 2.4; 2.5; 2.7 | Partial: metadata and typed resolvers exist. `connect()` is a mandatory non-spec burden, lifecycle methods are mandatory instead of optional capabilities, provider hooks are absent, and tracking is mandatory. | Model initialization, shutdown, provider hooks, and tracking as optional capabilities. Supply the initial global context and optional first-bound domain to initialization. Require idempotent shutdown behavior where implemented. | Minimal resolver-only provider, lifecycle provider, provider-hooks provider, tracking provider, and domain-scoped provider contract tests. | Keep `connect()` and mandatory legacy members behind an adapter while providers migrate to capability interfaces. |
| Hooks and evaluation options | 1.5.1; 2.3.1-2.3.3; 4.1-4.6 | Partial: API/client hooks and stages exist, but evaluation options, invocation hooks, provider hooks, supported-stage declarations, and fully immutable hints are missing. Custom priority ordering can conflict with specified registration order. | Add evaluation options and invocation hooks/hints. Add provider hooks. Implement before ordering API -> transaction -> client -> invocation -> provider and reverse after/error/finally order, limited by supported stages. Keep hook data immutable. | Stage signature, merge contribution, ordering, short-circuit/error, supported-stage, hint immutability, and late registration tests. | Deprecate custom priority semantics if they cannot be mapped without violating specification order. |
| Event API and isolation | 5.1.1-5.1.5; 5.2.1-5.2.7; 5.3.1-5.3.5 | Missing: `open_feature_event.dart` and `event_system.dart` define competing event types. Handler registration consumes an untyped stream, and association relies on provider names rather than instances/domains. | Publish one canonical event model. Register/remove handlers by event type at API and client scope. Isolate delivery by provider instance and dynamic domain binding, include required event metadata, and prevent handler failures from disrupting others. | Typed registration/removal, API/client scope, same-name instance isolation, rebinding, metadata, status-before-handler, and handler-failure tests. | Adapt legacy streams to the canonical dispatcher during a deprecation window; do not keep two independent event buses. |
| API shutdown and reset | 1.6.1-1.6.2; 1.7.6; 2.5 | Partial: focused provider shutdown infers `NOT_READY` without fabricating a stale event, and singleton reset awaits resilient controller/lifecycle cleanup even when one operation fails. A conformant API-wide shutdown that invokes every registered provider and resets all API state is still missing. | Add API shutdown that shuts down every registered provider once, resets providers, contexts, hooks, event handlers, and transaction propagators, and leaves the API reusable in its initial state. | Multi-provider shutdown-once, idempotency, in-flight initialization cancellation, complete state reset, partial-cleanup failure, and reuse-after-shutdown tests. | Keep `shutdownProvider` as a deprecated focused helper if needed, implemented through the lifecycle coordinator. |
| Independent API instances | 1.8.1-1.8.4 | Missing: only the global singleton is publicly available. | Add a deliberately separate factory/module for independent API instances with isolated providers, contexts, hooks, handlers, and transaction propagation. | Cross-instance state, event, provider, hook, and shutdown isolation tests. | Preserve the default singleton as the normal entry point. |
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
