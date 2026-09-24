# Typed provider events

The server API and its clients use one dispatcher for provider lifecycle
events. New applications register a handler for a specific event type:

```dart
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';

final api = OpenFeatureAPI();
final client = api.getClient('checkout');
void onError(OpenFeatureEvent event) {
  print('${event.providerName}: ${event.errorCode} ${event.errorMessage}');
}
client.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, onError);
// API handlers observe all tracked providers; client handlers follow bindings.
api.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, onError);
client.removeEventHandler(OpenFeatureEventType.PROVIDER_ERROR, onError);
api.removeEventHandler(OpenFeatureEventType.PROVIDER_ERROR, onError);
```

Keep the same callback reference for removal. Registering the same callback
twice for the same scope/type is idempotent. Handlers persist through provider
replacement. They run synchronously when dispatched, after the SDK updates
provider status; their returned futures are observed without blocking other
handlers. Both synchronous throws and asynchronous failures are logged and
contained. A handler added while its provider is already ready, stale, in
error/fatal, or reconciling runs immediately with the matching state. A
configuration-change event is a notification, not a replayable state.

Client routing uses provider identity and the requested domain, never just
the provider name. Unbound clients follow the default provider. During pending
initialization, clients keep their current evaluation binding. When a new
binding becomes active, its current state is delivered to those clients.
Provider-wide events reach every client using that instance; a domain binding
notification reaches only the affected domain. API handlers do not receive a
second provider event merely because another domain binds that instance.

`ProviderLifecycleEventType` is an alias for `OpenFeatureEventType`.
`ProviderLifecycleEvent` retains its existing constructor as a compatibility
subclass of `OpenFeatureEvent`. Providers keep using `ProviderEventSource`.
The SDK supplies provider identity/name; providers can supply `flagsChanged`,
`eventMetadata` (boolean, string or numeric values), message and error code.
The two new collections are copied and unmodifiable. Existing arbitrary `data`
payloads remain unchanged for compatibility.

The deprecated one-argument `addHandler` and existing `events` streams adapt
the same dispatcher. Streams keep their asynchronous Dart delivery semantics
and do not replay state; typed handlers give immediate state delivery. Ordinary
`events.listen` follows Dart's own listener-error semantics, while `addHandler`
contains callback failures. Dispose clients or cancel stream subscriptions when
finished. API disposal closes its client event scopes.

The old `event_system.dart` library contains standalone application telemetry
utilities with a different enum and constructor. It was never connected to
provider lifecycle events and is now deprecated for SDK event use; importing
it does not create an additional provider dispatcher. It remains available
for existing custom telemetry users until a separately reviewed removal.

This implements the event slice of the pinned OpenFeature v0.9.0 specification,
not complete server conformance. Static-context reconciliation remains outside
the dynamic-context server paradigm. Legacy provider initialization grace is
unchanged; reusable API shutdown and isolated API instances remain #163.

Requirement-indexed evidence is in `test/typed_events_test.dart`, alongside
the retained `provider_lifecycle_test.dart` and `provider_capabilities_test.dart`
initialization, status and replacement-race suites.
