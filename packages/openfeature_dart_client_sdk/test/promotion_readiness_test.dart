import 'dart:async';

import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart'
    show createIsolatedOpenFeatureAPI;
import 'package:test/test.dart';

void main() {
  group('beta promotion lifecycle safety', () {
    test(
      'a missing terminal event times out and releases the provider',
      () async {
        final api = createIsolatedOpenFeatureAPI(
          lifecycleTimeout: const Duration(milliseconds: 25),
        );
        final provider = _SilentLifecycleProvider();

        await expectLater(
          api.setProviderAndWait(provider),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('did not complete'),
            ),
          ),
        );

        expect(provider.shutdownCalls, 1);
        await api.shutdown().timeout(const Duration(seconds: 1));
      },
    );

    test(
      'initialization timeout stays bounded when shutdown never returns',
      () async {
        final api = createIsolatedOpenFeatureAPI(
          lifecycleTimeout: const Duration(milliseconds: 25),
        );
        final provider = _HungCleanupProvider();

        await expectLater(
          api.setProviderAndWait(provider).timeout(const Duration(seconds: 1)),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('initialization did not complete'),
            ),
          ),
        );

        expect(provider.shutdownCalls, 1);
        expect(api.getClient().providerStatus, ProviderStatus.notReady);
        await expectLater(
          api.setProviderAndWait(provider),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('cannot be reused'),
            ),
          ),
        );
        await api.shutdown().timeout(const Duration(seconds: 1));
      },
    );

    test('the final lifecycle event at callback return wins', () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.shutdown);
      final provider = _BackgroundErrorProvider();

      await api.setProviderAndWait(provider);

      expect(api.getClient().providerStatus, ProviderStatus.ready);
    });

    test('a provider that throws before an event is shut down', () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.shutdown);
      final provider = _ThrowingLifecycleProvider();

      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<StateError>()),
      );

      expect(provider.shutdownCalls, 1);
      expect(api.getClient().providerStatus, ProviderStatus.notReady);
    });

    test('context-aware providers cannot be shared across bindings', () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.shutdown);
      final provider = _ContextProvider();

      await api.setProviderForDomainAndWait('one', provider);

      await expectLater(
        api.setProviderForDomainAndWait('two', provider),
        throwsA(
          isA<OpenFeatureException>().having(
            (error) => error.message,
            'message',
            contains('only one active binding'),
          ),
        ),
      );
    });

    test('one provider instance cannot be active in two APIs', () async {
      final firstApi = createIsolatedOpenFeatureAPI();
      final secondApi = createIsolatedOpenFeatureAPI();
      addTearDown(firstApi.shutdown);
      addTearDown(secondApi.shutdown);
      final provider = InMemoryProvider({'flag': true});

      await firstApi.setProviderAndWait(provider);
      await expectLater(
        secondApi.setProviderAndWait(provider),
        throwsA(isA<OpenFeatureException>()),
      );

      await firstApi.shutdown();
      await secondApi.setProviderAndWait(provider);
      expect(secondApi.getClient().getBooleanValue('flag', false), isTrue);
    });
  });

  group('beta promotion evaluation and context safety', () {
    test(
      'API and client hooks observe provider hook discovery failures',
      () async {
        final api = createIsolatedOpenFeatureAPI();
        addTearDown(api.shutdown);
        final apiHook = _RecordingHook();
        final clientHook = _RecordingHook();
        api.addHooks([apiHook]);
        await api.setProviderAndWait(_ThrowingHooksProvider());
        final client = api.getClient()..addHooks([clientHook]);

        final details = client.getBooleanDetails('flag', false);

        expect(details.value, isFalse);
        expect(details.reason, 'ERROR');
        expect(apiHook.errors, 1);
        expect(apiHook.finallyCalls, 1);
        expect(clientHook.errors, 1);
        expect(clientHook.finallyCalls, 1);
      },
    );

    test(
      'a partial global context failure rolls back successful providers',
      () async {
        final api = createIsolatedOpenFeatureAPI();
        addTearDown(api.shutdown);
        final successful = _ContextProvider();
        final failing = _ContextProvider(failTargetingKey: 'rejected');
        await api.setProviderAndWait(successful);
        await api.setProviderForDomainAndWait('checkout', failing);
        final rejected = EvaluationContext(targetingKey: 'rejected');

        await expectLater(
          api.setEvaluationContextAndWait(rejected),
          throwsA(isA<OpenFeatureException>()),
        );

        expect(successful.activeContext, same(EvaluationContext.empty));
        expect(successful.changes, [
          (EvaluationContext.empty, rejected),
          (rejected, EvaluationContext.empty),
        ]);
        api.getClient().getBooleanValue('flag', false);
        expect(successful.lastEvaluationContext, same(EvaluationContext.empty));
      },
    );

    test(
      'a rollback failure quarantines its provider and preserves the original error',
      () async {
        final api = createIsolatedOpenFeatureAPI();
        addTearDown(api.shutdown);
        final rollbackFails = _ContextProvider(failRollback: true);
        final forwardFails = _ContextProvider(failTargetingKey: 'rejected');
        await api.setProviderAndWait(rollbackFails);
        await api.setProviderForDomainAndWait('checkout', forwardFails);

        await expectLater(
          api.setEvaluationContextAndWait(
            EvaluationContext(targetingKey: 'rejected'),
          ),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('ended with status error'),
            ),
          ),
        );

        expect(api.getClient().providerStatus, ProviderStatus.notReady);
        expect(api.getClient().getBooleanValue('flag', false), isFalse);
      },
    );

    test('a reconciliation timeout quarantines late provider work', () async {
      final api = createIsolatedOpenFeatureAPI(
        lifecycleTimeout: const Duration(milliseconds: 25),
      );
      addTearDown(api.shutdown);
      final delayed = _DelayedContextProvider();
      await api.setProviderAndWait(delayed);

      await expectLater(
        api.setEvaluationContextAndWait(
          EvaluationContext(targetingKey: 'delayed'),
        ),
        throwsA(
          isA<OpenFeatureException>().having(
            (error) => error.message,
            'message',
            contains('reconciliation did not complete'),
          ),
        ),
      );

      expect(api.getClient().providerStatus, ProviderStatus.notReady);
      await expectLater(
        api.setProviderAndWait(delayed),
        throwsA(
          isA<OpenFeatureException>().having(
            (error) => error.message,
            'message',
            contains('cannot be reused'),
          ),
        ),
      );

      final replacement = _ContextProvider();
      await api.setProviderAndWait(replacement);
      delayed.release();
      await delayed.finished;

      expect(api.getClient().providerStatus, ProviderStatus.ready);
      api.getClient().getBooleanValue('flag', false);
      expect(replacement.lastEvaluationContext, same(EvaluationContext.empty));
    });

    test(
      'cleanup timeout starts shutdown and quarantines the provider',
      () async {
        final api = createIsolatedOpenFeatureAPI(
          lifecycleTimeout: const Duration(milliseconds: 25),
        );
        addTearDown(api.shutdown);
        final provider = _HungCancellationProvider();
        await api.setProviderAndWait(provider);

        await expectLater(
          api.setProviderAndWait(InMemoryProvider({'replacement': true})),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('cleanup did not complete'),
            ),
          ),
        );

        expect(provider.shutdownCalls, 1);
        await expectLater(
          api.setProviderAndWait(provider),
          throwsA(
            isA<OpenFeatureException>().having(
              (error) => error.message,
              'message',
              contains('timed out cannot be reused'),
            ),
          ),
        );
      },
    );
  });
}

class _DelegatingProvider implements FeatureProvider {
  final InMemoryProvider _delegate = InMemoryProvider({'flag': true});

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'promotion-readiness-provider');

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => _delegate.resolveBooleanValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => _delegate.resolveDoubleValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => _delegate.resolveIntegerValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => _delegate.resolveStringValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => _delegate.resolveStructureValue(flagKey, defaultValue, context);
}

class _SilentLifecycleProvider extends _DelegatingProvider
    implements InitializableProvider, ProviderEventSource, ShutdownProvider {
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);
  int shutdownCalls = 0;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {}

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
    await _events.close();
  }
}

final class _BackgroundErrorProvider extends _SilentLifecycleProvider {
  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    _events.add(ProviderEvent(type: ProviderEventType.error));
    await Future<void>.delayed(Duration.zero);
    _events.add(ProviderEvent(type: ProviderEventType.ready));
  }
}

final class _ThrowingLifecycleProvider extends _SilentLifecycleProvider {
  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    throw StateError('initialization failed');
  }
}

final class _HungCleanupProvider extends _SilentLifecycleProvider {
  final Completer<void> _never = Completer<void>();

  @override
  Future<void> shutdown() {
    shutdownCalls++;
    return _never.future;
  }
}

class _ContextProvider extends _DelegatingProvider
    implements ContextReconciliationProvider, ProviderEventSource {
  _ContextProvider({this.failTargetingKey, this.failRollback = false});

  final String? failTargetingKey;
  final bool failRollback;
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);
  final List<(EvaluationContext, EvaluationContext)> changes = [];
  EvaluationContext activeContext = EvaluationContext.empty;
  EvaluationContext? lastEvaluationContext;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    changes.add((previousContext, newContext));
    if (failRollback &&
        previousContext.targetingKey == 'rejected' &&
        newContext.targetingKey == null) {
      throw StateError('rollback failed');
    }
    if (failTargetingKey != null &&
        newContext.targetingKey == failTargetingKey) {
      _events.add(ProviderEvent(type: ProviderEventType.error));
      return;
    }
    activeContext = newContext;
    _events.add(ProviderEvent(type: ProviderEventType.contextChanged));
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) {
    lastEvaluationContext = context;
    return super.resolveBooleanValue(flagKey, defaultValue, context);
  }
}

final class _HungCancellationProvider extends _DelegatingProvider
    implements ProviderEventSource, ShutdownProvider {
  final Completer<void> _cancellation = Completer<void>();
  late final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>(onCancel: () => _cancellation.future);
  int shutdownCalls = 0;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
  }
}

final class _DelayedContextProvider extends _ContextProvider {
  final Completer<void> _release = Completer<void>();
  final Completer<void> _finished = Completer<void>();

  Future<void> get finished => _finished.future;

  void release() => _release.complete();

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    await _release.future;
    try {
      await super.onContextChanged(previousContext, newContext);
    } finally {
      _finished.complete();
    }
  }
}

final class _ThrowingHooksProvider extends _DelegatingProvider
    implements ProviderHooks {
  @override
  List<Hook> get hooks => throw StateError('hook discovery failed');
}

final class _RecordingHook extends HookAdapter {
  int errors = 0;
  int finallyCalls = 0;

  @override
  void error(HookContext context, Object error, HookHints hints) {
    errors++;
  }

  @override
  void finallyAfter(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {
    finallyCalls++;
  }
}
