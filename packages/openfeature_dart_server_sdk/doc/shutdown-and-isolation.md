# Reusable shutdown and experimental isolated APIs

`await api.shutdown()` shuts down every tracked provider, including registered
providers that were never initialized. Multiple bindings to one provider do not
multiply shutdown calls. Concurrent shutdown calls share one operation. Cleanup
continues after a provider failure; the returned future reports the first failure
after all cleanup operations settle. The same API can be configured again even
when cleanup reports an error.

Shutdown removes API providers, domain bindings, API hooks, global evaluation
context, event handlers and transaction propagation state. Existing clients
resolve the reset API's initial no-op provider and return application defaults.
They follow newly configured providers after reuse. Client-owned hooks and
client-local evaluation context remain owned by that client; create another
client if those should be reset too.

```dart
final api = OpenFeatureAPI();
final client = api.getClient('checkout');
await api.shutdown();
// Reconfigure the same API and use the same client after shutdown completes.
```

Provider configuration and API mutation during shutdown throw `StateError`.
Evaluations from existing clients safely fall back while cleanup is in progress.
Old event subscriptions are detached and complete asynchronously; typed handlers
must be registered again after shutdown. Paused compatibility listeners do not
block shutdown, and old queued notifications are filtered out when they resume.

Shutdown requests provider cleanup immediately even when initialization is still
pending. Provider implementations are responsible for aborting their own startup
work (v0.9 requirement 2.5.2). The SDK cancels the old binding and ignores its late
events/results. It cannot stop arbitrary I/O inside an uncooperative provider.
That provider object stays reserved until its old initialization settles, so a
different API cannot race its late work by reusing the same object.

## Isolated instances (experimental)

The ordinary `OpenFeatureAPI()` factory remains the singleton. Advanced users
explicitly opt in through a separate import:

```dart
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';

final isolated = createIsolatedOpenFeatureAPI();
try {
  // Configure this instance without changing the singleton or another instance.
} finally {
  await isolated.dispose();
}
```

Each isolated API owns its providers, contexts, hooks, events and transaction
manager. Creating an isolated API does not change the process logging level or
attach another global logging sink. The internal annotated constructor is an
implementation bridge; application code should use the experimental import.

The same provider object cannot be registered with two active APIs. Registration
throws `StateError` before modifying the second API. This includes registration
through an SDK adapter obtained from an existing client. Multiple domains within
one API may share a provider, subject to the existing domain-scoped restriction.
After all registrations/bindings are removed and cleanup finishes, the object may
move to another API if the provider supports reinitialization. One-shot providers,
including the existing `InMemoryProvider`, still require a new provider object.

`api.transactionContextManager` supplies that API's transaction scope. The global
API retains the legacy `TransactionContextManager()` singleton for compatibility;
isolated APIs use independent managers and zone keys. Shutdown invalidates active
async transaction scopes as well as the calling zone, without clearing another
API's scopes. Propagator registration/removal and tracking are documented in
[tracking and transaction propagation](tracking-and-transactions.md).

## Existing cleanup APIs

- `shutdown()` resets the API for reuse and propagates cleanup to providers.
- `dispose()` permanently closes the instance and now also cleans up providers.
  Repeated calls share the same result. Use a new API after disposal.
- `OpenFeatureAPI.resetInstance()` disposes the old singleton before releasing
  it, even if cleanup fails. **It now reports provider cleanup failures that the
  previous listener-only disposal did not call or observe.** Handle its returned
  future in teardown code. Existing clients of the disposed API keep returning
  defaults; they do not become clients of the replacement singleton.
- `shutdownProvider()` retains its focused default-provider replacement behavior.
  It is not a substitute for API-wide shutdown and does not clear other domains.

Tests in `api_shutdown_isolation_test.dart` index requirements 1.6, 1.8 and 2.5,
alongside the retained provider lifecycle races. This slice does not claim full
server v0.9 conformance or change either package's release version.
