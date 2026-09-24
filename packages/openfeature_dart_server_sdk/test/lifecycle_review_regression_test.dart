import 'dart:async';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';
import 'package:openfeature_dart_server_sdk/provider_capabilities.dart';
import 'package:openfeature_dart_server_sdk/src/event_dispatcher.dart';
import 'package:openfeature_dart_server_sdk/src/provider_adapter.dart';
import 'package:openfeature_dart_server_sdk/src/provider_lifecycle_manager.dart';
import 'provider_capabilities_test.dart' show MinimalProvider;
import 'typed_events_test.dart' show EventProvider;

class ShutdownOnly extends MinimalProvider implements ProviderShutdown {
  int calls = 0;
  Completer<void>? gate;
  ShutdownOnly() : super(label: 'shutdown-only');
  @override
  Future<void> shutdownProvider() async {
    calls++;
    await gate?.future;
  }
}

class NamedEvents extends EventProvider {
  @override
  ProviderMetadata get metadata => const ProviderMetadata(name: 'retired');
}

void main() {
  test('late READY handler must not replay retired initial default', () async {
    final api = createIsolatedOpenFeatureAPI();
    addTearDown(api.dispose);
    await api.setProviderAndWait(MinimalProvider(label: 'active'));
    final names = <String?>[];
    api.addEventHandler(
      OpenFeatureEventType.PROVIDER_READY,
      (event) => names.add(event.providerName),
    );
    expect(names, ['active']);
  });

  test('late handler must not resubscribe to retired provider', () async {
    final api = createIsolatedOpenFeatureAPI();
    final retired = NamedEvents();
    addTearDown(() async {
      await api.dispose();
      await retired.controller.close();
    });
    await api.setProviderAndWait(retired);
    await api.setProviderAndWait(MinimalProvider(label: 'active'));
    expect(retired.controller.hasListener, isFalse);
    api.addEventHandler(OpenFeatureEventType.PROVIDER_READY, (_) {});
    expect(retired.controller.hasListener, isFalse);
  });

  test(
    'resolver-only provider shuts down twice across rebindings without reset',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.dispose);
      final provider = ShutdownOnly();
      await api.setProviderAndWait(provider);
      await api.setProviderAndWait(MinimalProvider(label: 'replacement-1'));
      expect(provider.calls, 1);
      await api.setProviderAndWait(provider);
      await api.setProviderAndWait(MinimalProvider(label: 'replacement-2'));
      expect(provider.calls, 2);
    },
  );

  test('scope closure must finish with a paused listener', () async {
    final dispatcher = EventDispatcher();
    final scope = dispatcher.scope(current: (_) => const []);
    final subscription = scope.events.listen((_) {})..pause();
    final closing = scope.close();
    try {
      await closing.timeout(const Duration(seconds: 1));
    } finally {
      await subscription.cancel();
      await closing;
      await dispatcher.close();
    }
  });

  test(
    'adapter caches failed shutdown until a new managed lifecycle',
    () async {
      final provider = ShutdownOnly()..gate = Completer<void>();
      final adapter = ResolverProviderAdapter(provider);
      final first = adapter.shutdownProvider();
      final concurrent = adapter.shutdownProvider();
      expect(concurrent, same(first));
      expect(provider.calls, 1);
      final observed = expectLater(first, throwsStateError);
      provider.gate!.completeError(StateError('controlled cleanup failure'));
      await observed;
      expect(adapter.shutdownProvider(), same(first));
      provider.gate = null;
      final manager = ProviderLifecycleManager((_, _) {});
      addTearDown(manager.dispose);
      await manager.initialize(adapter);
      manager.bindDefault(adapter);
      await manager.unbindDefault(adapter);
      await adapter.shutdownProvider();
      expect(provider.calls, 2);
    },
  );

  test('scope closure delivers done after a paused listener resumes', () async {
    final dispatcher = EventDispatcher();
    final scope = dispatcher.scope(current: (_) => const []);
    final done = Completer<void>();
    final subscription = scope.events.listen((_) {}, onDone: done.complete)
      ..pause();
    try {
      await dispatcher.close().timeout(const Duration(seconds: 1));
      expect(done.isCompleted, isFalse);
      subscription.resume();
      await done.future.timeout(const Duration(seconds: 1));
    } finally {
      await subscription.cancel();
    }
  });
}
