# Required evaluation defaults and client metadata

This additive migration addresses issue #158 against OpenFeature v0.9.0.
It does not claim complete server conformance: evaluation options and hook
normalization remain tracked in #161, with final evidence in #165.

## New application code

Import the existing `package:openfeature_dart_server_sdk/client.dart` library.
Use the `RequiredDefaultEvaluation` extension's methods:

```dart
final enabled = await client.getBooleanValue(
  'matchingEnabled',
  defaultValue: false,
);
final details = await client.getBooleanEvaluationDetails(
  'matchingEnabled',
  defaultValue: false,
);
```

Boolean, String, Integer, Double and Object each have a `get*Value` and
`get*EvaluationDetails` method. All ten methods require a named `defaultValue`
argument. The context remains optional and evaluation remains asynchronous.
The analyzer fixture verifies that all ten omitted-default calls fail.

The application chooses the fallback. A provider error, unavailable provider,
or failed evaluation returns that exact supplied value. A structured fallback
retains its object identity; the SDK does not mutate it. A provider returning an
error alongside a different value cannot substitute its own fallback. Detailed
results use `ERROR` and preserve the provider's error code/message. The error
normalization also applies to the existing API and its error hooks.

## Existing consumers

The existing `get*Flag` and `get*Details` methods, optional defaults, import
paths, package name and provider signatures continue to work. No new runtime
dependency, Flutter dependency, transport, or package-version change is added.
The legacy compile fixture covers all ten methods without explicit defaults.

Migration stages:

1. This change introduces required-default alternatives and recommends them
   for new code. Legacy methods remain available without analyzer warnings.
2. After maintainers review downstream adoption, a separate release may add
   analyzer deprecations. That release must document affected consumers.
3. Removal or signature changes require a separately reviewed breaking release
   and migration notice. This change sets no automatic removal date.

The compatibility methods do not enforce required arguments and must not be
advertised as doing so. They are deliberately retained during migration.

## Client metadata

`client.metadata.domain` is the domain requested at creation, even while the
client falls back to the default provider or follows later provider rebinding.
With `getClient(name, domain: domain)`, the explicit domain wins. Without an
explicit domain, the existing name-based binding uses `name` as the domain.
The legacy `metadata.name` remains the supplied name for source compatibility.
Metadata attributes are copied and exposed through an unmodifiable map.

## Evidence

- `test/evaluation_foundations_test.dart`: independently reproduced provider
  fallback and caller-owned metadata mutation defects; fixed behavior.
- `test/required_defaults_test.dart`: five types, value/details methods,
  provider errors, type mismatch, thrown errors, NOT_READY/FATAL short-circuit,
  failed provider lookup, immutable domain across fallback/rebinding, and
  analyzer-based required-argument/legacy compatibility fixtures.
- Existing provider lifecycle and dynamic rebinding tests remain required.

Baseline: https://github.com/open-feature/spec/tree/v0.9.0/specification
