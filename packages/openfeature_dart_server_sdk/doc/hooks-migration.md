# Hooks and evaluation options migration

This change implements the server hook slice in issue #161 against OpenFeature
**v0.9.0**. It is not a claim of complete SDK conformance. Implemented
[typed events](events-migration.md), [shutdown and isolated APIs](shutdown-and-isolation.md),
and [tracking](tracking-and-transactions.md) have their own migration guides.
The [conformance evidence](../../../doc/server-conformance-evidence.md) records
remaining semantic, compatibility and release gates. The server uses dynamic evaluation context; the static-context
condition 4.3.3.1 is not applicable.

## New usage

Import `client.dart`, `evaluation_context.dart`, and `hooks.dart` alongside
`open_feature_api.dart`. All five `get*Value` and `get*EvaluationDetails` methods
accept optional `EvaluationOptions`; the ten legacy methods accept it too.

```dart
final audit = EvaluationHook(
  metadata: const HookMetadata(name: 'audit'),
  before: (context, hints) {
    context.hookData.set('started', DateTime.now());
    return EvaluationContext.immutable(attributes: {'source': 'server'});
  },
  after: (context, details, hints) {
    print('${context.flagKey}: ${details.value} (${details.reason})');
  },
  error: (context, error, hints) {
    print('Evaluation failed: $error');
  },
  finallyAfter: (context, details, hints) {
    // Details describe the result actually returned, including error defaults.
    final started = context.hookData.get('started') as DateTime?;
    if (started != null) print(DateTime.now().difference(started));
  },
);

final result = await client.getBooleanValue(
  'checkout-enabled',
  defaultValue: false,
  context: EvaluationContext.immutable(targetingKey: 'user-123'),
  options: EvaluationOptions(
    hooks: [audit],
    hints: HookHints.immutable({'requestId': 'request-456'}),
  ),
);
```

A runnable version is in `example/hook_options_example.dart`. `EvaluationHook`
requires at least one callback. Callback arguments are typed; `before` returns
an optional canonical `EvaluationContext`. `finallyAfter` is the Dart spelling
of the specification's final stage. Only supplied stages run.

## Registration and ordering

- API: `api.addEvaluationHooks([hook])`; existing clients see additions on their
  next evaluation. Legacy `api.addHooks(List<OpenFeatureHook>)` remains supported.
  Both registration methods contribute to the same API insertion sequence.
- Client: `client.addHook(hook)` or `client.addHooks([hook])`.
- Invocation: `EvaluationOptions(hooks: [hook])`.
- Provider: implement `ProviderHooks` and expose `List<Hook> get hooks`.

Before order is **API -> client -> invocation -> provider**, with insertion order
within each scope. After/error/finally reverse both scope and insertion order.
Each evaluation captures one sequence and uses it throughout; registrations and
removals during an await affect the next invocation. Transaction context supplies
evaluation fields, not a fifth hook scope.

**Compatibility decision:** SDK evaluations now ignore `HookPriority`. Previously,
priority could silently reverse registration order, contrary to 4.4.2. Register
hooks in the desired order instead. The standalone `HookManager.executeHooks`
helper retains its legacy priority ordering when no explicit execution sequence
is supplied. `HookConfig.continueOnError` does not override the specification's
stage failure rules. No old hook method is removed or analyzer-deprecated here.

## Immutable inputs and mutable hook data

`EvaluationOptions` copies the hook list and snapshots hints on construction.
`HookHints.immutable` captures nested maps/lists and rejects unsupported values,
non-string map keys and cycles. Hints accept string keys and boolean, string,
number, DateTime and structured values; `targetingKey` is an ordinary hint key.
Top-level hint values cannot be null; nested structures may contain null. This
hint-specific rule does not restrict evaluation contexts, which accept null at
every depth. The legacy const `HookHints` constructor remains; its caller-owned
values are captured when wrapped in options or supplied to a new typed hook.
Direct standalone execution of legacy hooks retains its existing hints.

Registering a new `EvaluationHook` opts that hook into private immutable snapshots
of its evaluation-context view and structured defaults/results. Its default is
captured before provider execution, including for an after-only hook. Context
views are captured per callback; they do not freeze the provider's legacy input
for the whole invocation. Use `EvaluationContext.immutable` or `.snapshot()` to
capture caller-owned evaluation data at its source. Client and provider metadata
are immutable in the new hook context.

Typed before-hook contributions are captured before merging into subsequent
hooks and provider inputs. Partial contributions survive a later before failure
for error/finally observers. This does not change legacy `Hook`/`BaseHook` context,
default or result value types and identities. Legacy nested aliasing and mutable
outer provider maps remain as documented in the context migration guide. The
public `EvaluationDetails` constructor also retains its legacy value behavior;
the SDK supplies private snapshots to new typed callbacks.

Invalid values encountered by typed-hook snapshots return the application's
exact fallback. Context-validation errors use `INVALID_CONTEXT`; invalid default
or result snapshots use `GENERAL`. Error/finally hooks still run: values that
cannot be represented as immutable snapshots are preserved as legacy diagnostic
references in those cleanup callbacks. Those invalid values carry no deep
immutability guarantee. Registering a typed hook with existing opaque context
data therefore requires an explicit compatibility review.

`HookData` is intentionally **mutable** and accepts arbitrary Dart objects. It is
isolated by hook object identity and invocation, survives across supported stages,
and is created before the first supported stage. Reusing the same hook object
at several scopes shares that object's data within one evaluation. Distinct
objects remain isolated even if they implement equal `operator ==` values.

## Failures and result details

Before/after failure stops that stage, returns the application's exact default,
and invokes error then finally in reverse order. Error/finally failure or timeout
cannot suppress remaining cleanup hooks. Provider lookup failures also reach
registered API/client/invocation error and finally hooks. Provider hooks are
available only once a provider has been resolved.

Structured defaults supplied by the application retain their return identity;
typed hooks receive an immutable private copy when valid. `EvaluationDetails` now carries
`errorCode`, `errorMessage` and `flagMetadata`. Its value, reason, variant, errors,
metadata and evaluation time match the application details on success/failure.
Legacy hooks receive hints on every stage through `HookContext.hints`, details
through `HookContext.evaluationDetails`, and the existing final-stage arguments.

Hook timeouts bound how long evaluation waits. Dart futures cannot forcibly cancel
user code; hooks should manage their own resources and cancellation. Cleanup
failures are contained without attempting to format an exception or read failing
hook metadata again.

## Reproducible checks

From `packages/openfeature_dart_server_sdk`:

```sh
dart pub get
dart test test/hooks_regression_test.dart test/hook_contract_test.dart
dart test test/hook_legacy_compatibility_test.dart test/context_review_regression_test.dart
dart test
dart analyze
dart run example/hook_options_example.dart
```

The three regression cases fail on the pre-fix integration: late API hooks run
zero times, priorities reverse registration, and an after failure returns false
while finally observes true. They pass with this implementation.

| Requirements | Evidence |
| --- | --- |
| 4.1.1-4.1.5; 4.2.2 | Immutable runtime fields/defaults/metadata across await; mutable arbitrary HookData; exact fallback identity |
| 4.2.1; 4.5.1-4.5.3 | Deep immutable hints, supported values, invalid values/cycles, hints at all stages |
| 4.3.1-4.3.2; 4.6.1 | Stage declaration, first-supported-stage data creation, identity isolation, concurrent invocations |
| 4.3.2.1; 4.3.4-4.3.5 | Canonical context contributions, targeting precedence, provider input and original-input preservation |
| 4.3.6-4.3.9.1 | Typed callbacks and finallyAfter; success/error details; per-type before/after failure defaults |
| 4.4.1-4.4.2; 2.3 | All four scopes, reversed cleanup, late registration, stable in-flight sequence and removal |
| 4.4.3-4.4.7 | Short-circuit, remaining cleanup after exceptions, timeout, failing metadata, unformattable exception and provider lookup |
| Evaluation options across types | All twenty canonical/legacy value/detail methods exercise invocation hooks and hints |
| Legacy coexistence and failure containment | `hook_legacy_compatibility_test.dart`: opaque/typed/cyclic legacy values, original defaults/results, after-only capture, invalid typed inputs/results and continued error/finally cleanup |

External compatibility was checked with IntelliToggle's canonical GitLab provider
source and PairQueue's backend using local dependency overrides. These are local
candidate checks, not live service, flag-refresh or deployed application evidence.
