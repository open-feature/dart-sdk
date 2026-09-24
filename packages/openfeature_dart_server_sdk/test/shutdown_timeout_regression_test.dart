import 'dart:async';

import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:openfeature_dart_server_sdk/src/provider_adapter.dart';
import 'package:openfeature_dart_server_sdk/src/provider_lifecycle_manager.dart';
import 'package:openfeature_dart_server_sdk/src/provider_ownership.dart';
import 'package:test/test.dart';

import 'api_shutdown_isolation_test.dart' show ProbeProvider;
import 'lifecycle_review_regression_test.dart' show ShutdownOnly;

class SlowCancellationProvider extends ProbeProvider
    implements ProviderEventSource {
  final StreamController<ProviderLifecycleEvent> controller;
  SlowCancellationProvider(
    Completer<void> shutdown,
    Completer<void> cancellation,
  ) : controller = StreamController<ProviderLifecycleEvent>(
        onCancel: () => cancellation.future,
      ),
      super(shutdownGate: shutdown);
  @override
  Stream<ProviderLifecycleEvent> get providerEvents => controller.stream;
}

void main() {
  test('resolver-only rebind during shutdown restores READY', () async {
    final events = <ProviderLifecycleEvent>[];
    final manager = ProviderLifecycleManager((_, event) => events.add(event));
    addTearDown(manager.dispose);
    final provider = ShutdownOnly()..gate = Completer<void>();
    final adapter = ResolverProviderAdapter(provider);
    await manager.initialize(adapter);
    manager.bindDefault(adapter);
    final shutdown = manager.unbindDefault(adapter);
    expect(provider.calls, 1);
    final rebind = manager.initialize(adapter);
    provider.gate!.complete();
    await Future.wait([shutdown, rebind]);
    expect(manager.trackedStatusOf(adapter), ProviderState.READY);
    expect(
      events.where((e) => e.type == ProviderLifecycleEventType.PROVIDER_READY),
      hasLength(2),
    );
    manager.bindDefault(adapter);
    await manager.unbindDefault(adapter);
    expect(provider.calls, 2);
  });

  test('stalled provider shutdown returns a bounded provider error', () async {
    final api = createIsolatedOpenFeatureAPI();
    final gate = Completer<void>();
    final provider = ProbeProvider(shutdownGate: gate);
    await api.setProviderAndWait(provider);
    final shutdown = api.shutdown();
    try {
      await expectLater(
        shutdown.timeout(const Duration(seconds: 15)),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.code,
            'code',
            ErrorCode.GENERAL,
          ),
        ),
      );
      expect(provider.stopped, 1);
      await expectLater(api.setProviderAndWait(provider), throwsStateError);
      await api.setProviderAndWait(ProbeProvider(label: 'replacement'));
      expect(api.providerStatus, ProviderState.READY);
    } finally {
      gate.complete();
      await shutdown.catchError((Object _) {});
      await api.dispose();
    }
  });

  for (final operation in ['dispose', 'resetInstance']) {
    test(
      '$operation completes with a provider timeout and detaches old work',
      () async {
        final api = operation == 'resetInstance'
            ? OpenFeatureAPI()
            : createIsolatedOpenFeatureAPI();
        final gate = Completer<void>();
        final provider = ProbeProvider(shutdownGate: gate);
        await api.setProviderAndWait(provider);
        final closing = operation == 'resetInstance'
            ? OpenFeatureAPI.resetInstance()
            : api.dispose();
        try {
          await expectLater(
            closing.timeout(const Duration(seconds: 15)),
            throwsA(isA<ProviderException>()),
          );
          final fresh = operation == 'resetInstance'
              ? OpenFeatureAPI()
              : createIsolatedOpenFeatureAPI();
          try {
            expect(fresh, isNot(same(api)));
            await expectLater(
              fresh.setProviderAndWait(provider),
              throwsStateError,
            );
            await fresh.setProviderAndWait(ProbeProvider(label: 'fresh'));
            expect(fresh.providerStatus, ProviderState.READY);
          } finally {
            await fresh.dispose();
            if (operation == 'resetInstance')
              await OpenFeatureAPI.resetInstance();
          }
        } finally {
          gate.complete();
          await Future<void>.delayed(Duration.zero);
        }
      },
    );
  }

  test(
    'resolver timeout retires record, blocks reuse, and permits late completion',
    () async {
      final gate = Completer<void>();
      final provider = ShutdownOnly()..gate = gate;
      final adapter = ResolverProviderAdapter(provider);
      final retired = <FeatureProvider>[];
      final manager = ProviderLifecycleManager(
        (_, _) {},
        onRetired: retired.add,
        shutdownTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(manager.dispose);
      await manager.initialize(adapter);
      manager.bindDefault(adapter);
      final stopping = manager.unbindDefault(adapter);
      // A concurrent rebind must not start a lifecycle over timed-out cleanup.
      final rebind = manager.initialize(adapter);
      final rejected = expectLater(rebind, throwsStateError);
      await expectLater(stopping, throwsA(isA<ProviderException>()));
      await rejected;
      expect(manager.trackedStatusOf(adapter), isNull);
      expect(retired, [adapter]);
      expect(provider.calls, 1);
      expect(
        () => ProviderOwnership.claim(provider, Object()),
        throwsStateError,
      );
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      final owner = Object();
      ProviderOwnership.claim(provider, owner);
      ProviderOwnership.release(provider, owner);
      await manager.initialize(adapter);
      manager.bindDefault(adapter);
      await manager.unbindDefault(adapter);
      expect(provider.calls, 2);
    },
  );

  test(
    'one stalled cleanup does not prevent other providers from shutting down',
    () async {
      final gate = Completer<void>();
      final slow = ShutdownOnly()..gate = gate;
      final fast = ShutdownOnly();
      final manager = ProviderLifecycleManager(
        (_, _) {},
        shutdownTimeout: const Duration(milliseconds: 20),
      );
      manager.track(ResolverProviderAdapter(slow));
      manager.track(ResolverProviderAdapter(fast));
      try {
        final first = manager.shutdownAll();
        expect(manager.shutdownAll(), same(first));
        await expectLater(first, throwsA(isA<ProviderException>()));
        expect([slow.calls, fast.calls], [1, 1]);
      } finally {
        gate.completeError(StateError('late cleanup failure'));
        await Future<void>.delayed(Duration.zero);
        await manager.dispose();
      }
    },
  );

  test(
    'quarantine waits for every pending cleanup before allowing reuse',
    () async {
      final cleanup = Completer<void>();
      final cancel = Completer<void>();
      final provider = SlowCancellationProvider(cleanup, cancel);
      final manager = ProviderLifecycleManager(
        (_, _) {},
        shutdownTimeout: const Duration(milliseconds: 20),
      );
      manager.track(provider);
      await expectLater(
        manager.shutdownAll(),
        throwsA(isA<ProviderException>()),
      );
      expect(manager.trackedStatusOf(provider), isNull);
      cancel.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        () => ProviderOwnership.ensureAvailable(provider),
        throwsStateError,
      );
      cleanup.completeError(StateError('late shutdown error'));
      await Future<void>.delayed(Duration.zero);
      ProviderOwnership.ensureAvailable(provider);
      await manager.dispose();
      await provider.controller.close();
    },
  );
}
