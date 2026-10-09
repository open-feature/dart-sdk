import 'dart:async';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';
import 'package:test/test.dart';
import 'api_shutdown_isolation_test.dart' show ProbeProvider;
import 'shutdown_timeout_regression_test.dart' show SlowCancellationProvider;
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';

class PublicCancellationProvider extends SlowCancellationProvider {
  PublicCancellationProvider(super.shutdown, super.cancellation);
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    await super.initialize(config);
    controller.add(
      ProviderLifecycleEvent(
        ProviderLifecycleEventType.PROVIDER_READY,
        'initialized',
      ),
    );
  }
}

void main() {
  for (final singleton in [true, false]) {
    test(
      '${singleton ? 'singleton' : 'isolated'} public timeout validates and survives shutdown/reuse',
      () async {
        await OpenFeatureAPI.resetInstance();
        final api = singleton
            ? OpenFeatureAPI()
            : createIsolatedOpenFeatureAPI();
        try {
          expect(api.providerShutdownTimeout, const Duration(seconds: 5));
          expect(
            () => api.providerShutdownTimeout = Duration.zero,
            throwsArgumentError,
          );
          expect(
            () =>
                api.providerShutdownTimeout = const Duration(microseconds: -1),
            throwsArgumentError,
          );
          expect(api.providerShutdownTimeout, const Duration(seconds: 5));
          api.providerShutdownTimeout = const Duration(milliseconds: 40);
          await api.shutdown();
          expect(api.providerShutdownTimeout, const Duration(milliseconds: 40));
          await api.setProviderAndWait(ProbeProvider());
          await api.shutdown();
          expect(api.providerShutdownTimeout, const Duration(milliseconds: 40));
        } finally {
          await api.dispose();
          await OpenFeatureAPI.resetInstance();
        }
        expect(
          () => api.providerShutdownTimeout = const Duration(seconds: 1),
          throwsStateError,
        );
      },
    );
  }

  test(
    'public setting keeps in-flight cleanup deadline and quarantine',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      final other = createIsolatedOpenFeatureAPI();
      final gate = Completer<void>();
      final provider = ProbeProvider(shutdownGate: gate);
      try {
        api.providerShutdownTimeout = const Duration(milliseconds: 40);
        await api.setProviderAndWait(provider);
        final cleanup = api.shutdown();
        final check = expectLater(
          cleanup,
          throwsA(
            isA<ProviderException>().having(
              (error) => error.details?['timeoutMs'],
              'original deadline',
              40,
            ),
          ),
        );
        await provider.stopping.future;
        api.providerShutdownTimeout = const Duration(seconds: 2);
        await check;
        expect(api.providerShutdownTimeout, const Duration(seconds: 2));
        await expectLater(other.setProviderAndWait(provider), throwsStateError);
        gate.complete();
        await Future<void>.delayed(Duration.zero);
        await other.setProviderAndWait(provider);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await api.dispose();
        await other.dispose();
      }
    },
  );

  test('provider replacement uses the public configured deadline', () async {
    final api = createIsolatedOpenFeatureAPI();
    final gate = Completer<void>();
    final old = ProbeProvider(shutdownGate: gate, label: 'old');
    final errors = <OpenFeatureEvent>[];
    try {
      api.providerShutdownTimeout = const Duration(milliseconds: 30);
      api.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, errors.add);
      await api.setProviderAndWait(old);
      await api.setProviderAndWait(ProbeProvider(label: 'new'));
      expect(api.provider.metadata.name, 'new');
      final error = errors.single.data as ProviderException;
      expect(error.details?['timeoutMs'], 30);
      expect(error.details?['operation'], 'shutdown');
    } finally {
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await api.dispose();
    }
  });

  test(
    'in-flight cleanup keeps one captured deadline across both phases',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      final shutdown = Completer<void>();
      final cancellation = Completer<void>();
      final provider = PublicCancellationProvider(shutdown, cancellation);
      try {
        api.providerShutdownTimeout = const Duration(milliseconds: 40);
        await api.setProviderAndWait(provider);
        final cleanup = api.shutdown();
        final check = expectLater(
          cleanup.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<ProviderException>().having(
              (error) => error.details?['timeoutMs'],
              'captured deadline',
              40,
            ),
          ),
        );
        await provider.stopping.future;
        // Reading the new value for phase two would wait two seconds and fail
        // the one-second safety bound, rather than completing both 40ms phases.
        api.providerShutdownTimeout = const Duration(seconds: 2);
        await check;
      } finally {
        shutdown.complete();
        cancellation.complete();
        await Future<void>.delayed(Duration.zero);
        await api.dispose();
        await provider.controller.close();
      }
    },
  );

  test('public timeout also bounds event cancellation', () async {
    final api = createIsolatedOpenFeatureAPI();
    final shutdown = Completer<void>()..complete();
    final cancellation = Completer<void>();
    final provider = PublicCancellationProvider(shutdown, cancellation);
    try {
      api.providerShutdownTimeout = const Duration(milliseconds: 30);
      await api.setProviderAndWait(provider);
      await expectLater(
        api.shutdown(),
        throwsA(
          isA<ProviderException>()
              .having(
                (error) => error.details?['operation'],
                'phase',
                'event cancellation',
              )
              .having((error) => error.details?['timeoutMs'], 'deadline', 30),
        ),
      );
    } finally {
      cancellation.complete();
      await Future<void>.delayed(Duration.zero);
      await api.dispose();
      await provider.controller.close();
    }
  });
}
