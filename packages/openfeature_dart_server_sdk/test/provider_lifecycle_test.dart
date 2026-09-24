import 'dart:async';

import 'package:test/test.dart';

import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:openfeature_dart_server_sdk/src/provider_lifecycle_manager.dart';

class _LegacyProvider implements FeatureProvider {
  final String providerName;
  final Map<String, dynamic> flags;
  ProviderState _state;
  int initializeCount = 0;
  int shutdownCount = 0;

  _LegacyProvider(
    this.flags, {
    this.providerName = 'provider',
    ProviderState initialState = ProviderState.NOT_READY,
  }) : _state = initialState;

  @override
  String get name => providerName;

  @override
  ProviderState get state => _state;

  @override
  ProviderConfig get config => const ProviderConfig();

  @override
  ProviderMetadata get metadata => ProviderMetadata(name: providerName);

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    initializeCount++;
    _state = ProviderState.READY;
  }

  @override
  Future<void> connect() async {
    _state = ProviderState.READY;
  }

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    _state = ProviderState.SHUTDOWN;
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final value = flags[flagKey];
    if (value is bool) {
      return _result(flagKey, value);
    }
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      value == null ? ErrorCode.FLAG_NOT_FOUND : ErrorCode.TYPE_MISMATCH,
      'Boolean flag not found.',
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final value = flags[flagKey];
    return value is String
        ? _result(flagKey, value)
        : FlagEvaluationResult.error(
            flagKey,
            defaultValue,
            ErrorCode.FLAG_NOT_FOUND,
            'String flag not found.',
            evaluatorId: name,
          );
  }

  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final value = flags[flagKey];
    return value is int
        ? _result(flagKey, value)
        : FlagEvaluationResult.error(
            flagKey,
            defaultValue,
            ErrorCode.FLAG_NOT_FOUND,
            'Integer flag not found.',
            evaluatorId: name,
          );
  }

  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final value = flags[flagKey];
    return value is double
        ? _result(flagKey, value)
        : FlagEvaluationResult.error(
            flagKey,
            defaultValue,
            ErrorCode.FLAG_NOT_FOUND,
            'Double flag not found.',
            evaluatorId: name,
          );
  }

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final value = flags[flagKey];
    return value is Map<String, dynamic>
        ? _result(flagKey, value)
        : FlagEvaluationResult.error(
            flagKey,
            defaultValue,
            ErrorCode.FLAG_NOT_FOUND,
            'Object flag not found.',
            evaluatorId: name,
          );
  }

  FlagEvaluationResult<T> _result<T>(String flagKey, T value) {
    return FlagEvaluationResult<T>(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {}
}

class _EventProvider extends _LegacyProvider implements ProviderEventSource {
  final StreamController<ProviderLifecycleEvent> _events =
      StreamController<ProviderLifecycleEvent>.broadcast();
  final bool emitReady;
  final bool failInitialization;
  final Duration readyEventDelay;

  _EventProvider(
    super.flags, {
    super.providerName,
    this.emitReady = true,
    this.failInitialization = false,
    this.readyEventDelay = Duration.zero,
  });

  @override
  Stream<ProviderLifecycleEvent> get providerEvents => _events.stream;

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    initializeCount++;
    if (failInitialization) {
      _state = ProviderState.ERROR;
      _events.add(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_ERROR,
          'Provider initialization failed.',
          errorCode: ErrorCode.PROVIDER_FATAL,
        ),
      );
      throw const ProviderException(
        'Provider initialization failed.',
        code: ErrorCode.PROVIDER_FATAL,
      );
    }

    _state = ProviderState.READY;
    if (emitReady) {
      void emitReadyEvent() => _events.add(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_READY,
          'Provider is ready.',
        ),
      );
      if (readyEventDelay == Duration.zero) {
        emitReadyEvent();
      } else {
        unawaited(Future<void>.delayed(readyEventDelay, emitReadyEvent));
      }
    }
  }

  void emit(ProviderLifecycleEvent event) => _events.add(event);
}

class _DelayedShutdownEventProvider extends _EventProvider {
  final Completer<void> shutdownStarted = Completer<void>();
  final Completer<void> allowShutdown = Completer<void>();

  _DelayedShutdownEventProvider(super.flags);

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    if (!shutdownStarted.isCompleted) {
      shutdownStarted.complete();
    }
    await allowShutdown.future;
    _state = ProviderState.SHUTDOWN;
  }
}

class _FailingShutdownEventProvider extends _EventProvider {
  final Completer<void> shutdownStarted = Completer<void>();
  final Completer<void> allowShutdown = Completer<void>();

  _FailingShutdownEventProvider(super.flags);

  @override
  Future<void> shutdown() async {
    shutdownCount++;
    if (!shutdownStarted.isCompleted) {
      shutdownStarted.complete();
    }
    await allowShutdown.future;
    throw StateError('shutdown failed');
  }
}

class _CancelFailureEventProvider extends _EventProvider {
  final StreamController<ProviderLifecycleEvent> _cancelFailureEvents =
      StreamController<ProviderLifecycleEvent>.broadcast();

  _CancelFailureEventProvider(super.flags);

  @override
  Stream<ProviderLifecycleEvent> get providerEvents =>
      _CancelFailureStream(_cancelFailureEvents.stream);

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    initializeCount++;
    _state = ProviderState.READY;
    _cancelFailureEvents.add(
      ProviderLifecycleEvent(
        ProviderLifecycleEventType.PROVIDER_READY,
        'Provider is ready.',
      ),
    );
  }

  Future<void> closeEvents() => _cancelFailureEvents.close();
}

class _CancelFailureStream extends Stream<ProviderLifecycleEvent> {
  final Stream<ProviderLifecycleEvent> _delegate;

  const _CancelFailureStream(this._delegate);

  @override
  StreamSubscription<ProviderLifecycleEvent> listen(
    void Function(ProviderLifecycleEvent event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CancelFailureSubscription(
    _delegate.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    ),
  );
}

class _CancelFailureSubscription
    implements StreamSubscription<ProviderLifecycleEvent> {
  final StreamSubscription<ProviderLifecycleEvent> _delegate;

  _CancelFailureSubscription(this._delegate);

  @override
  Future<void> cancel() async {
    await _delegate.cancel();
    throw StateError('subscription cancellation failed');
  }

  @override
  void onData(void Function(ProviderLifecycleEvent data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture(futureValue);
}

class _DomainScopedProvider extends _EventProvider
    implements DomainScopedProvider {
  _DomainScopedProvider(super.flags);
}

void main() {
  group('OpenFeature v0.9 provider lifecycle', () {
    setUp(() async {
      await OpenFeatureAPI.resetInstance();
    });

    tearDown(() async {
      await OpenFeatureAPI.resetInstance();
    });

    test('provider event updates status before API handlers run', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider({'flag': true});
      final observedStatuses = <ProviderState>[];
      final events = <OpenFeatureEvent>[];
      final subscription = api.events.listen((event) {
        if (identical(event.provider, provider)) {
          events.add(event);
          observedStatuses.add(api.providerStatus);
        }
      });

      await api.setProviderAndWait(provider);
      await Future<void>.delayed(Duration.zero);

      expect(api.providerStatus, ProviderState.READY);
      expect(events, hasLength(1));
      expect(events.single.type, OpenFeatureEventType.PROVIDER_READY);
      expect(observedStatuses, [ProviderState.READY]);
      await subscription.cancel();
    });

    test(
      'existing clients receive readiness for a newly bound provider',
      () async {
        final api = OpenFeatureAPI();
        final client = api.getClient('client');
        final provider = _EventProvider({'flag': true});
        final events = <OpenFeatureEvent>[];
        final subscription = client.events.listen(events.add);

        await api.setProviderAndWait(provider);
        await Future<void>.delayed(Duration.zero);

        expect(
          events.where(
            (event) =>
                event.type == OpenFeatureEventType.PROVIDER_READY &&
                identical(event.provider, provider),
          ),
          hasLength(1),
        );
        await subscription.cancel();
        await client.dispose();
      },
    );

    test(
      'event-capable provider must emit within the lifecycle timeout',
      () async {
        final api = OpenFeatureAPI();
        final provider = _EventProvider({'flag': true}, emitReady: false);
        final lifecycleEvents = <OpenFeatureEvent>[];
        final subscription = api.events.listen((event) {
          if (identical(event.provider, provider)) {
            lifecycleEvents.add(event);
          }
        });

        await expectLater(
          api.setProviderAndWait(provider),
          throwsA(
            isA<ProviderException>().having(
              (error) => error.message,
              'message',
              contains('did not emit a lifecycle event within'),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(identical(api.provider, provider), isTrue);
        expect(api.providerStatus, ProviderState.NOT_READY);
        expect(lifecycleEvents, isEmpty);
        await subscription.cancel();
      },
    );

    test('provider error event sets fatal status without synthesis', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider({'flag': true}, failInitialization: true);
      final events = <OpenFeatureEvent>[];
      final subscription = api.events.listen((event) {
        if (identical(event.provider, provider)) {
          events.add(event);
        }
      });

      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<ProviderException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.providerStatus, ProviderState.FATAL);
      expect(events, hasLength(1));
      expect(events.single.type, OpenFeatureEventType.PROVIDER_ERROR);
      expect(events.single.errorCode, ErrorCode.PROVIDER_FATAL);
      await subscription.cancel();
    });

    test(
      'temporarily tolerates a legacy event delivered after initialize',
      () async {
        final api = OpenFeatureAPI();
        final provider = _EventProvider({
          'flag': true,
        }, readyEventDelay: const Duration(milliseconds: 20));

        await api.setProviderAndWait(provider);

        expect(api.providerStatus, ProviderState.READY);
        expect(provider.initializeCount, 1);
      },
    );

    test(
      'legacy providers retain synthesized lifecycle compatibility',
      () async {
        final api = OpenFeatureAPI();
        final provider = _LegacyProvider({'flag': true});
        final events = <OpenFeatureEvent>[];
        final subscription = api.events.listen((event) {
          if (identical(event.provider, provider)) {
            events.add(event);
          }
        });

        await api.setProviderAndWait(provider);
        await Future<void>.delayed(Duration.zero);

        expect(api.providerStatus, ProviderState.READY);
        expect(events, hasLength(1));
        expect(events.single.type, OpenFeatureEventType.PROVIDER_READY);
        await subscription.cancel();
      },
    );

    test(
      'legacy error events preserve the provider state they observed',
      () async {
        final provider = _LegacyProvider({
          'flag': true,
        }, initialState: ProviderState.CONNECTING);
        ProviderLifecycleEvent? observedEvent;
        final manager = ProviderLifecycleManager((source, event) {
          observedEvent = event;
        });

        await expectLater(
          manager.initialize(provider),
          throwsA(isA<ProviderException>()),
        );

        expect(observedEvent?.data, containsPair('state', 'CONNECTING'));
        expect(manager.statusOf(provider), ProviderState.ERROR);
        await manager.dispose();
      },
    );

    test('already-ready legacy provider still announces readiness', () async {
      final api = OpenFeatureAPI();
      final provider = _LegacyProvider({
        'flag': true,
      }, initialState: ProviderState.READY);
      final events = <OpenFeatureEvent>[];
      final subscription = api.events.listen((event) {
        if (identical(event.provider, provider)) {
          events.add(event);
        }
      });

      await api.setProviderAndWait(provider);
      await Future<void>.delayed(Duration.zero);

      expect(provider.initializeCount, 0);
      expect(events, hasLength(1));
      expect(events.single.type, OpenFeatureEventType.PROVIDER_READY);
      await subscription.cancel();
    });

    test('existing clients follow default provider replacement', () async {
      final api = OpenFeatureAPI();
      final first = _EventProvider({'flag': true}, providerName: 'shared');
      final second = _EventProvider({'flag': false}, providerName: 'shared');

      await api.setProviderAndWait(first);
      final client = api.getClient('existing-client');
      expect(await client.getBooleanFlag('flag'), isTrue);

      await api.setProviderAndWait(second);

      expect(identical(client.provider, second), isTrue);
      expect(client.providerStatus, ProviderState.READY);
      expect(await client.getBooleanFlag('flag'), isFalse);
    });

    test('rebinding waits for an in-progress provider shutdown', () async {
      final api = OpenFeatureAPI();
      final first = _DelayedShutdownEventProvider({'flag': true});
      final second = _EventProvider({'flag': false});

      await api.setProviderAndWait(first);
      final replacement = api.setProviderAndWait(second);
      await first.shutdownStarted.future;

      var rebindCompleted = false;
      final rebind = api.setProviderAndWait(first).then((_) {
        rebindCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(rebindCompleted, isFalse);
      expect(first.initializeCount, 1);

      first.allowShutdown.complete();
      await Future.wait([replacement, rebind]);

      expect(first.initializeCount, 2);
      expect(identical(api.provider, first), isTrue);
      expect(api.providerStatus, ProviderState.READY);
    });

    test('rebinding recovers after an in-progress shutdown fails', () async {
      final api = OpenFeatureAPI();
      final first = _FailingShutdownEventProvider({'flag': true});
      final replacement = _EventProvider({
        'flag': false,
      }, providerName: 'replacement');

      await api.setProviderAndWait(first);
      final replacementBinding = api.setProviderAndWait(replacement);
      await first.shutdownStarted.future;

      final rebind = api.setProviderAndWait(first);
      first.allowShutdown.complete();
      await Future.wait([replacementBinding, rebind]);

      expect(first.initializeCount, 2);
      expect(identical(api.provider, first), isTrue);
      expect(api.providerStatus, ProviderState.READY);
      // Reset now propagates provider shutdown too. The rebound provider's
      // second lifecycle still fails cleanup, but the API must reset anyway.
      await expectLater(api.shutdown(), throwsStateError);
      expect(first.shutdownCount, 2);
    });

    test('latest concurrent default provider request wins', () async {
      final api = OpenFeatureAPI();
      final slow = _EventProvider(
        {'flag': true},
        providerName: 'slow',
        readyEventDelay: const Duration(milliseconds: 30),
      );
      final fast = _EventProvider({'flag': false}, providerName: 'fast');

      final slowBinding = api.setProviderAndWait(slow);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await api.setProviderAndWait(fast);
      await slowBinding;

      expect(identical(api.provider, fast), isTrue);
      expect(await api.getClient('client').getBooleanFlag('flag'), isFalse);
      expect(slow.shutdownCount, 1);
    });

    test('a superseded default remains live when still registered', () async {
      final api = OpenFeatureAPI();
      final slow = _EventProvider(
        {'flag': true},
        providerName: 'slow',
        readyEventDelay: const Duration(milliseconds: 30),
      );
      final fast = _EventProvider({'flag': false}, providerName: 'fast');
      api.registerProvider(slow, providerId: 'registered-slow');

      final slowBinding = api.setProviderAndWait(slow);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await api.setProviderAndWait(fast);
      await slowBinding;

      expect(identical(api.provider, fast), isTrue);
      expect(slow.shutdownCount, isZero);
      await api.bindClientToProviderAndWait('registered', 'registered-slow');
      expect(
        identical(api.getClient('client', domain: 'registered').provider, slow),
        isTrue,
      );
    });

    test(
      'concurrent requests for the same default do not shut it down',
      () async {
        final api = OpenFeatureAPI();
        final provider = _EventProvider({
          'flag': true,
        }, readyEventDelay: const Duration(milliseconds: 20));

        final firstBinding = api.setProviderAndWait(provider);
        final secondBinding = api.setProviderAndWait(provider);
        await Future.wait([firstBinding, secondBinding]);

        expect(identical(api.provider, provider), isTrue);
        expect(provider.initializeCount, 1);
        expect(provider.shutdownCount, isZero);
        expect(api.providerStatus, ProviderState.READY);
      },
    );

    test('shutdown supersedes an in-flight default provider request', () async {
      final api = OpenFeatureAPI();
      final slow = _EventProvider(
        {'flag': true},
        providerName: 'slow',
        readyEventDelay: const Duration(milliseconds: 30),
      );

      final binding = api.setProviderAndWait(slow);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await api.shutdownProvider();
      await binding;

      expect(api.provider.metadata.name, 'InMemoryProvider');
      expect(api.providerStatus, ProviderState.READY);
      expect(slow.shutdownCount, 1);
    });

    test('same-name instances remain isolated by provider ID', () async {
      final api = OpenFeatureAPI();
      final first = _EventProvider({'flag': true}, providerName: 'shared');
      final second = _EventProvider({'flag': false}, providerName: 'shared');

      await api.registerProviderAndWait(first, providerId: 'shared-blue');
      await api.registerProviderAndWait(second, providerId: 'shared-green');
      await api.bindClientToProviderAndWait('blue', 'shared-blue');
      await api.bindClientToProviderAndWait('green', 'shared-green');

      final blue = api.getClient('blue', domain: 'blue');
      final green = api.getClient('green', domain: 'green');
      final blueEvents = <OpenFeatureEvent>[];
      final greenEvents = <OpenFeatureEvent>[];
      final blueSubscription = blue.events.listen(blueEvents.add);
      final greenSubscription = green.events.listen(greenEvents.add);

      expect(await blue.getBooleanFlag('flag'), isTrue);
      expect(await green.getBooleanFlag('flag'), isFalse);

      second.emit(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_STALE,
          'Green provider is stale.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(blueEvents, isEmpty);
      expect(greenEvents, hasLength(1));
      expect(green.providerStatus, ProviderState.STALE);
      await blueSubscription.cancel();
      await greenSubscription.cancel();
      await blue.dispose();
      await green.dispose();
    });

    test('domain clients receive global context change events', () async {
      final api = OpenFeatureAPI();
      final defaultProvider = _EventProvider({
        'flag': true,
      }, providerName: 'default');
      final domainProvider = _EventProvider({
        'flag': false,
      }, providerName: 'domain');
      await api.setProviderAndWait(defaultProvider);
      await api.setProviderForDomainAndWait(
        'checkout',
        domainProvider,
        providerId: 'domain',
      );
      final client = api.getClient('client', domain: 'checkout');
      final events = <OpenFeatureEvent>[];
      final subscription = client.events.listen(events.add);

      api.setGlobalContext(OpenFeatureEvaluationContext({'tenant': 'new'}));
      await Future<void>.delayed(Duration.zero);

      expect(
        events.where(
          (event) =>
              event.type == OpenFeatureEventType.PROVIDER_CONTEXT_CHANGED,
        ),
        hasLength(1),
      );
      await subscription.cancel();
      await client.dispose();
    });

    test('legacy name-first binding activates after registration', () async {
      final api = OpenFeatureAPI();
      api.bindClientToProvider('checkout', 'late-provider');
      final client = api.getClient('checkout', domain: 'checkout');
      final provider = _EventProvider({'flag': true});

      await api.registerProviderAndWait(provider, providerId: 'late-provider');

      expect(identical(client.provider, provider), isTrue);
      expect(client.providerStatus, ProviderState.READY);
      expect(provider.initializeCount, 1);
      expect(await client.getBooleanFlag('flag'), isTrue);
    });

    test(
      'provider shuts down only after its final binding is removed',
      () async {
        final api = OpenFeatureAPI();
        final first = _EventProvider({'flag': true}, providerName: 'first');
        final replacement = _EventProvider({
          'flag': false,
        }, providerName: 'replacement');

        await api.setProviderAndWait(first);
        api.registerProvider(first, providerId: 'first-domain');
        await api.bindClientToProviderAndWait('checkout', 'first-domain');

        await api.setProviderAndWait(replacement);
        expect(first.shutdownCount, 0);

        api.registerProvider(replacement, providerId: 'replacement-domain');
        await api.bindClientToProviderAndWait('checkout', 'replacement-domain');

        expect(first.shutdownCount, 1);
        expect(replacement.shutdownCount, 0);
      },
    );

    test('event provider can be rebound after final shutdown', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider({'flag': true}, providerName: 'first');
      final replacement = _EventProvider({
        'flag': false,
      }, providerName: 'replacement');

      await api.setProviderAndWait(provider);
      await api.setProviderAndWait(replacement);
      await api.setProviderAndWait(provider);

      expect(provider.initializeCount, 2);
      expect(provider.shutdownCount, 1);
      expect(api.providerStatus, ProviderState.READY);
    });

    test('legacy provider can be rebound after final shutdown', () async {
      final api = OpenFeatureAPI();
      final provider = _LegacyProvider({'flag': true}, providerName: 'first');
      final replacement = _LegacyProvider({
        'flag': false,
      }, providerName: 'replacement');

      await api.setProviderAndWait(provider);
      await api.setProviderAndWait(replacement);
      await api.setProviderAndWait(provider);

      expect(provider.initializeCount, 2);
      expect(provider.shutdownCount, 1);
      expect(api.providerStatus, ProviderState.READY);
    });

    test('shut-down providers stop forwarding lifecycle events', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider({'flag': true}, providerName: 'first');
      final replacement = _EventProvider({
        'flag': false,
      }, providerName: 'replacement');
      final forwarded = <OpenFeatureEvent>[];
      final subscription = api.events.listen((event) {
        if (identical(event.provider, provider)) {
          forwarded.add(event);
        }
      });

      await api.setProviderAndWait(provider);
      await api.setProviderAndWait(replacement);
      forwarded.clear();
      provider.emit(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_STALE,
          'Stale after shutdown.',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(forwarded, isEmpty);
      await subscription.cancel();
    });

    test('non-wait binding activates only after provider readiness', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider(
        {'flag': true},
        providerName: 'delayed',
        readyEventDelay: const Duration(milliseconds: 20),
      );
      api.registerProvider(provider, providerId: 'delayed');
      final client = api.getClient('checkout', domain: 'checkout');
      final configured = api.events.firstWhere(
        (event) =>
            event.type == OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED &&
            event.domain == 'checkout',
      );

      api.bindClientToProvider('checkout', 'delayed');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(identical(client.provider, provider), isFalse);
      await configured;
      expect(identical(client.provider, provider), isTrue);
      expect(client.providerStatus, ProviderState.READY);
    });

    test('domain-scoped provider rejects a second domain', () async {
      final api = OpenFeatureAPI();
      final provider = _DomainScopedProvider({'flag': true});

      await api.registerProviderAndWait(provider, providerId: 'scoped');
      await api.bindClientToProviderAndWait('domain-a', 'scoped');

      await expectLater(
        api.bindClientToProviderAndWait('domain-b', 'scoped'),
        throwsA(
          isA<ProviderException>().having(
            (error) => error.code,
            'code',
            ErrorCode.INVALID_CONTEXT,
          ),
        ),
      );
    });

    test('failed domain binding restores the prior pending binding', () async {
      final api = OpenFeatureAPI();
      final scoped = _DomainScopedProvider({'flag': true});
      final pending = _EventProvider({'flag': false}, providerName: 'pending');
      api.bindClientToProvider('domain-b', 'pending');
      await api.registerProviderAndWait(scoped, providerId: 'scoped');
      await api.bindClientToProviderAndWait('domain-a', 'scoped');

      await expectLater(
        api.bindClientToProviderAndWait('domain-b', 'scoped'),
        throwsA(
          isA<ProviderException>().having(
            (error) => error.code,
            'code',
            ErrorCode.INVALID_CONTEXT,
          ),
        ),
      );

      await api.registerProviderAndWait(pending, providerId: 'pending');
      final client = api.getClient('client', domain: 'domain-b');
      expect(identical(client.provider, pending), isTrue);
      expect(await client.getBooleanFlag('flag'), isFalse);
    });

    test('disposed APIs do not re-arm provider lifecycle tracking', () async {
      final api = OpenFeatureAPI();
      final provider = _EventProvider({'flag': true});
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      await OpenFeatureAPI.resetInstance();
      final uncaughtErrors = <Object>[];

      await runZonedGuarded(() async {
        expect(
          await client.getBooleanFlag('flag', defaultValue: false),
          isFalse,
        );
        provider.emit(
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_STALE,
            'Late stale event.',
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) => uncaughtErrors.add(error));

      expect(uncaughtErrors, isEmpty);
      await client.dispose();
    });

    test(
      'reset cancels an in-flight provider binding without late commits',
      () async {
        final api = OpenFeatureAPI();
        final provider = _EventProvider({
          'flag': true,
        }, readyEventDelay: const Duration(milliseconds: 30));
        final binding = api.setProviderAndWait(provider);
        final bindingExpectation = expectLater(binding, throwsStateError);

        await OpenFeatureAPI.resetInstance();

        await bindingExpectation;
        expect(identical(OpenFeatureAPI(), api), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 35));
      },
    );

    test(
      'reset releases the singleton even when disposal reports an error',
      () async {
        final original = OpenFeatureAPI();
        final provider = _CancelFailureEventProvider({'flag': true});
        await original.setProviderAndWait(provider);

        await expectLater(OpenFeatureAPI.resetInstance(), throwsStateError);

        expect(identical(OpenFeatureAPI(), original), isFalse);
        await provider.closeEvents();
      },
    );

    test('unbinding an untracked provider is a no-op', () async {
      final provider = _LegacyProvider({
        'flag': true,
      }, initialState: ProviderState.READY);
      final manager = ProviderLifecycleManager((provider, event) {});

      await manager.unbindDefault(provider);
      await manager.unbindDomain(provider, 'unknown');

      expect(provider.shutdownCount, isZero);
      await manager.dispose();
    });
  });
}
