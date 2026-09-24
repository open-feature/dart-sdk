# Optional provider capabilities

This additive migration implements the provider-surface work in
[#160](https://github.com/open-feature/dart-server-sdk/issues/160), against
[OpenFeature v0.9.0 section 2](https://github.com/open-feature/spec/blob/v0.9.0/specification/sections/02-providers.md).
Full hook/options, event API, shutdown/independent-instance and tracking details
work remains in #161-#164. This is not a full SDK conformance declaration.

## New providers

Implement `Provider` from `feature_provider.dart`. It requires only `metadata`
and five typed resolvers: `getBooleanFlag`, `getStringFlag`, `getIntegerFlag`,
`getDoubleFlag` and `getObjectFlag`. Each resolver receives a required flag key
and application default, plus optional context, and returns typed resolution
details. No `name`, `state`, configuration, `connect`, lifecycle or tracking
members are required. Supply transport/configuration through your own provider
constructor; the SDK does not prescribe a vendor transport.

Pass the provider directly to `setProvider`, `setProviderAndWait`,
`registerProvider`, `registerProviderAndWait` or `setProviderForDomainAndWait`.
The API adapts it internally for existing client code, reusing one adapter per
provider object in that API. Same-name objects remain distinct. Legacy client
provider getters/streams expose that stable internal adapter for new providers;
do not depend on its implementation type. Existing `FeatureProvider` objects
are not wrapped and retain their existing identity.

The complete `MinimalProvider` in `test/provider_capabilities_test.dart` uses
`implements Provider` with no superclass, mixin or lifecycle stubs. Its test
evaluates all five types and calls tracking without a tracking capability.

## Capabilities

Import `provider_capabilities.dart` and implement only the interfaces you need:

| Interface | Contract |
| --- | --- |
| `ProviderInitialization` | `initializeProvider(EvaluationContext context, {String? domain})` plus provider-owned `providerEvents`. |
| `ProviderShutdown` | `shutdownProvider()` releases resources; the SDK bridge prevents duplicate shutdown calls until another initialization. |
| `ProviderHooks` | A `hooks` list is captured per evaluation and participates in the existing hook lifecycle. |
| `ProviderTracking` | `trackEvent(name, evaluationContext: ..., trackingDetails: ...)` receives tracking calls; absent capability is a no-op. |

Lifecycle methods retain asynchronous Dart signatures. Tracking currently keeps
the existing asynchronous contract; its full nonblocking API/numeric/details
normalization is explicitly #164.

Without initialization, a provider starts ready and is not required to emit an
initialization event (2.8.5). An event source may still emit later changes.
Initialization receives an immutable snapshot of the **global** context at the
first initialization request; request/client context is not substituted for it.
The first supplied domain is retained even when concurrent or subsequent
bindings use other domains. Default-provider initialization has no domain.

The optional `DomainScopedProvider` marker from `provider_lifecycle.dart`
restricts a new provider to its first domain. Such a provider must implement
initialization to receive the domain. Initialize it through
`setProviderForDomainAndWait(domain, provider)` rather than pre-initializing it
as a default provider or using `registerProviderAndWait` without a domain.

New initialization capabilities must emit ready/error **before the
initialization future terminates**. Both synchronous streams and normal Dart
asynchronous delivery are supported. Missing or contradictory events reject
initialization; a late ready event cannot repair an invalid initialization.
The legacy one-second grace does not apply to new capability providers.

Provider before hooks follow application before hooks; provider after/error/
finally hooks precede the corresponding application hooks. Returned context
fields join the existing immutable context pipeline. Invocation options,
supported-stage declarations, complete application registration ordering and
immutable hints remain #161. Provider hooks do not run for tracking calls.

## Existing providers

`FeatureProvider` remains source-compatible and now implements the minimal
`Provider` contract. Existing providers can continue unchanged. Their old
`initialize([config])` signature still receives its old arguments; global
evaluation data is not passed as if it were vendor configuration.

The named `LegacyProviderLifecycleAdapter` centralizes the compatibility policy:
legacy lifecycle methods still run, providers without events have synthesized
ready/error transitions, and eventful legacy providers retain the existing
one-second delivery grace after initialization returns. This is explicitly a
legacy migration allowance, not the v0.9 timing contract. No removal date or
analyzer deprecation is introduced in this stage; removal requires a reviewed
provider migration and release. Existing `connect` remains a legacy method,
not part of the minimal provider contract.

To migrate incrementally, a legacy `FeatureProvider` may implement
`ProviderInitialization`, `ProviderShutdown`, `ProviderHooks` or
`ProviderTracking` as appropriate. Initialization/shutdown capabilities take
precedence over their old lifecycle methods. Complete migration to `Provider`
then removes obsolete mandatory stubs. Preserve provider-owned events and
transport/authentication in the external provider repository.

## Verification

From the server package run:

```sh
dart pub get
dart test test/provider_capabilities_test.dart test/provider_lifecycle_test.dart
dart test
dart analyze
```

The capability fixtures cover minimal resolution, absent/supported tracking and
hooks, initialization context/domain, concurrent first binding, ready/error
ordering, missing/contradictory events, domain-scoped enforcement, final-binding
shutdown/idempotency, same-name replacement races and unchanged legacy identity.
Existing replacement, lifecycle and legacy grace tests remain required.
