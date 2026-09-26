# Experimental tracking and transaction propagation

`client.trackEvent(name, context: ..., trackingDetails: ...)` returns `void` and
starts tracking without waiting for transport. Synchronous and asynchronous
provider failures are logged and contained. The existing `Future<void> track`
remains available for callers that await transport completion. Neither method
runs evaluation hooks. A resolver-only provider without `ProviderTracking` ignores
tracking; legacy `FeatureProvider.track` implementations remain supported.

Tracking uses the same context merge as evaluation: API, transaction, client,
then invocation. Invocation fields win, including `targetingKey`. The optional
`ProviderTracking` capability receives the resulting provider map.

```dart
client.trackEvent(
  'checkout',
  context: EvaluationContext.immutable(targetingKey: 'customer-123'),
  trackingDetails: TrackingEventDetails.immutable(
    value: 3,
    attributes: {'currency': 'USD', 'cart': {'items': ['sku-1']}},
  ),
);
```

The immutable constructor validates boolean, string, numeric and structured
custom fields and freezes nested maps/lists. Structures use string map keys and
may contain null. Dates, opaque objects and cycles are rejected. The legacy
const constructor retains caller-owned attributes without new validation.

**Numeric migration:** `TrackingEventDetails.value` is now `num?`, preserving
integer values without conversion to double. Existing double arguments and
const construction work. Code assigning the property directly to `double?`
must use `details.value?.toDouble()` or accept `num?`. This is a source-level
widening for readers that first shipped in **server 0.0.26**, not 0.0.25.
Brian accepted `num?` as spec-aligned in
[#164](https://github.com/open-feature/dart-sdk/issues/164#issuecomment-5831397075).

### Release-note correction

The [0.0.26 GitHub release](https://github.com/open-feature/dart-sdk/releases/tag/v0.0.26)
now identifies `double?` to `num?` as a **breaking source change** and includes
`details.value?.toDouble()`. The repository's generated 0.0.26 changelog entry
carries a one-time correction reviewed through the normal pull-request process.
The already-published pub.dev archive and immutable tag remain unchanged, so
that archive's original changelog does not contain the correction. Release Please
continues to own future entries; this does not request a new version, rewrite a
tag, or apply a repository-wide breaking-change footer to the client package.

## Transaction carriers

Import `experimental/transaction_context.dart` to opt into the carrier contract.
Register one carrier per API, then supply canonical context around request work:

```dart
api.setTransactionContextPropagator(ZoneTransactionContextPropagator());
await api.setTransactionContext(
  EvaluationContext.immutable(targetingKey: 'customer-123'),
  () async {
    await handleRequest();
  },
);
api.setTransactionContextPropagator(null); // Remove the carrier.
```

The zone carrier snapshots input before the operation starts. Nested scopes
restore the outer scope after success or failure; concurrent async requests use
separate scopes. Nested supplied context replaces the outer carrier context;
merge it explicitly when inheritance is wanted. Dart zones do not cross isolate
boundaries. A custom carrier must honor the same request-local contract; do not
share one carrier between APIs.

Without a carrier, `setTransactionContext` still executes the callback but ignores
its context. Registering another carrier replaces the current carrier. Removal,
replacement and API shutdown invalidate old SDK-created carrier scopes, even
when the same carrier object is registered again. Shutdown also clears the
registration; configure it again before reuse.

The existing `TransactionContextManager.withContext` remains supported, including
parent attribute inheritance. It supplies transaction fields when no explicit
carrier is registered. An explicit carrier takes precedence over this legacy
manager. Duplicate legacy transaction IDs now retain separate stack frames.

## Transport cleanup

The SDK does not define a tracking flush operation or guarantee delivery. A
buffering provider owns its queue, error policy and drain deadline. Implement
`ProviderShutdown` (or legacy `shutdown`) to flush or abandon pending work under
that policy. API shutdown invokes provider cleanup and awaits its returned
future; new calls resolve the reset API's no-op provider. Do not interpret
completion as vendor acknowledgment unless the provider explicitly promises it.

Providers should flush within the SDK's fixed five-second shutdown deadline or
flush on their own schedule before shutdown. The separate cancellation deadline
is not an additional tracking-flush budget. A timeout stops waiting without
cancelling provider I/O; exiting the process at that point can lose queued events.
See [shutdown and isolation](shutdown-and-isolation.md),
[#163](https://github.com/open-feature/dart-sdk/issues/163) and the public deadline
configuration follow-up [#196](https://github.com/open-feature/dart-sdk/issues/196).

`tracking_transaction_contract_test.dart` covers the implemented 2.7, 3.3 and
section 6 behavior, including a provider-owned pending transport drain. These
features remain experimental under the pinned [v0.9.0 specification](https://github.com/open-feature/spec/tree/v0.9.0/specification).
The complete conformance and release decision remains #165.
