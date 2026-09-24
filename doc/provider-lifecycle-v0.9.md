# OpenFeature v0.9 provider lifecycle migration

Status: implementation preview

Tracks: [#121](https://github.com/open-feature/dart-sdk/issues/121)

OpenFeature v0.9 makes the provider the source of lifecycle events. The SDK
updates provider status from those events before it invokes API or client event
handlers.

## Event-capable providers

A provider opts into the v0.9 lifecycle contract by implementing
`ProviderEventSource` in addition to `FeatureProvider`:

```dart
final events = StreamController<ProviderLifecycleEvent>.broadcast();

@override
Stream<ProviderLifecycleEvent> get providerEvents => events.stream;

@override
Future<void> initialize([Map<String, dynamic>? config]) async {
  try {
    await initializeVendorSdk();
    events.add(
      ProviderLifecycleEvent(
        ProviderLifecycleEventType.PROVIDER_READY,
        'Provider is ready.',
      ),
    );
  } catch (error) {
    events.add(
      ProviderLifecycleEvent(
        ProviderLifecycleEventType.PROVIDER_ERROR,
        'Provider initialization failed.',
        data: error,
        errorCode: ErrorCode.PROVIDER_FATAL,
      ),
    );
    rethrow;
  }
}
```

The SDK subscribes before calling `initialize`. OpenFeature v0.9 requires the
corresponding ready or error event to be emitted before that call terminates.
The SDK currently accepts delivery for a bounded interval afterward only as a
migration tolerance for legacy asynchronous event sources. That grace period is
not part of the provider contract and providers must not depend on it. The SDK
does not synthesize a missing event for a provider that implements
`ProviderEventSource`; `setProviderAndWait` fails with a contract error when the
expected event does not arrive in time.

Providers that do not implement `ProviderEventSource` continue to work through
the legacy lifecycle adapter. That path derives ready/error events from
`initialize` and `state` and is retained only for migration compatibility.

## Provider identity and domains

Provider metadata names are descriptive and are not instance identifiers.
Register same-name instances with explicit SDK identifiers:

```dart
await openFeature.registerProviderAndWait(
  blueProvider,
  providerId: 'checkout-blue',
);
await openFeature.registerProviderAndWait(
  greenProvider,
  providerId: 'checkout-green',
);

await openFeature.bindClientToProviderAndWait(
  'checkout-blue-domain',
  'checkout-blue',
);
```

Existing clients resolve their provider binding dynamically. Replacing the
default or domain provider therefore updates clients that were created before
the replacement.

A provider that implements the `DomainScopedProvider` marker can be bound to
only one domain. The SDK rejects a second distinct domain binding for the same
instance.

## Shutdown behavior

The SDK tracks default and domain bindings by provider instance. Replacing one
binding does not shut down a provider that is still used by another binding.
The provider is shut down once after its final binding is removed, and the SDK
then records its status as `NOT_READY` as required by OpenFeature v0.9.
