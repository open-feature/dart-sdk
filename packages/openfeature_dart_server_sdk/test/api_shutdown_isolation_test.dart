import 'dart:async';

import 'package:logging/logging.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:openfeature_dart_server_sdk/provider_capabilities.dart';
import 'package:openfeature_dart_server_sdk/transaction_context.dart';
import 'package:test/test.dart';

class ProbeProvider extends InMemoryProvider {
  final String label;
  final Completer<void>? initializeGate;
  final Completer<void>? shutdownGate;
  final bool failShutdown;
  final entered = Completer<void>();
  final stopping = Completer<void>();
  int initialized = 0;
  int stopped = 0;
  Map<String, dynamic>? context;
  ProbeProvider({
    this.label = 'probe',
    this.initializeGate,
    this.shutdownGate,
    this.failShutdown = false,
  }) : super({'flag': true});

  @override
  ProviderMetadata get metadata => ProviderMetadata(name: label);
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    initialized++;
    if (!entered.isCompleted) entered.complete();
    await initializeGate?.future;
    // This fixture explicitly supports reinitialization; the stock in-memory
    // provider is deliberately one-shot after its own shutdown.
    setState(ProviderState.NOT_READY);
    await super.initialize(config);
  }

  @override
  Future<void> shutdown() async {
    stopped++;
    if (!stopping.isCompleted) stopping.complete();
    await shutdownGate?.future;
    await super.shutdown();
    if (failShutdown) throw StateError('fixture shutdown failure');
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool fallback, {
    Map<String, dynamic>? context,
  }) {
    this.context = context;
    return super.getBooleanFlag(key, fallback, context: context);
  }
}

class EventProbe extends ProbeProvider implements ProviderEventSource {
  final controller = StreamController<ProviderLifecycleEvent>.broadcast(
    sync: true,
  );
  EventProbe({super.initializeGate});
  @override
  Stream<ProviderLifecycleEvent> get providerEvents => controller.stream;
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    await super.initialize(config);
    emit(OpenFeatureEventType.PROVIDER_READY);
  }

  void emit(OpenFeatureEventType type) =>
      controller.add(ProviderLifecycleEvent(type, 'probe'));
}

class CountingHook implements OpenFeatureHook {
  int calls = 0;
  @override
  void beforeEvaluation(String key, Map<String, dynamic>? context) => calls++;
  @override
  void afterEvaluation(
    String key,
    dynamic result,
    Map<String, dynamic>? context,
  ) {}
}

class ResolverWithShutdown implements Provider, ProviderShutdown {
  int stopped = 0;
  @override
  ProviderMetadata get metadata => const ProviderMetadata(name: 'resolver');
  Future<FlagEvaluationResult<T>> result<T>(String key, T value) async =>
      FlagEvaluationResult(
        flagKey: key,
        value: value,
        reason: 'STATIC',
        evaluatedAt: DateTime.now(),
      );
  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool fallback, {
    Map<String, dynamic>? context,
  }) => result(key, true);
  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String key,
    String fallback, {
    Map<String, dynamic>? context,
  }) => result(key, fallback);
  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String key,
    int fallback, {
    Map<String, dynamic>? context,
  }) => result(key, fallback);
  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String key,
    double fallback, {
    Map<String, dynamic>? context,
  }) => result(key, fallback);
  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String key,
    Map<String, dynamic> fallback, {
    Map<String, dynamic>? context,
  }) => result(key, fallback);
  @override
  Future<void> shutdownProvider() async {
    stopped++;
  }
}

class FailingContext extends TransactionContext {
  FailingContext()
    : super(transactionId: 'broken', attributes: {'stale': true});
  @override
  void cleanup() {
    super.cleanup();
    throw StateError('context cleanup failed');
  }
}

void main() {
  final instances = <OpenFeatureAPI>[];
  OpenFeatureAPI isolated() {
    final api = createIsolatedOpenFeatureAPI();
    instances.add(api);
    return api;
  }

  tearDown(() async {
    for (final api in instances) {
      await api.dispose();
    }
    instances.clear();
    await OpenFeatureAPI.resetInstance();
  });

  test(
    '1.8.4: final registration replacement releases ownership without API shutdown',
    () async {
      final first = isolated();
      final second = isolated();
      final provider = ProbeProvider();
      await first.registerProviderAndWait(provider, providerId: 'slot');
      await first.registerProviderAndWait(ProbeProvider(), providerId: 'slot');
      await Future<void>.delayed(Duration.zero);
      expect(provider.stopped, 1);
      await second.setProviderAndWait(provider);
      expect(provider.initialized, 2);
    },
  );

  test(
    '1.6 / 1.8.4: resolver-only shutdown capability resets on each lifecycle',
    () async {
      final first = isolated();
      final second = isolated();
      final provider = ResolverWithShutdown();
      await first.setProviderAndWait(provider);
      final adapter = first.provider;
      await expectLater(second.setProviderAndWait(adapter), throwsStateError);
      await first.shutdown();
      await first.setProviderAndWait(provider);
      await first.shutdown();
      expect(provider.stopped, 2);
      await second.setProviderAndWait(adapter);
      await second.shutdown();
      expect(provider.stopped, 3);
    },
  );

  test(
    '1.6.2: context cleanup failure still clears state and allows reuse',
    () async {
      final api = isolated();
      api.transactionContextManager.pushContext(FailingContext());
      api.setGlobalContext(OpenFeatureEvaluationContext({'old': true}));
      await expectLater(api.shutdown(), throwsStateError);
      expect(api.transactionContextManager.currentContext, isNull);
      expect(api.globalContext, isNull);
      await api.setProviderAndWait(ProbeProvider());
      expect(await api.getClient('new').getBooleanFlag('flag'), isTrue);
    },
  );

  test(
    'dispose during shutdown shares provider cleanup and prevents reuse',
    () async {
      final api = isolated();
      final gate = Completer<void>();
      final provider = ProbeProvider(shutdownGate: gate);
      await api.setProviderAndWait(provider);
      final shutdown = api.shutdown();
      await provider.stopping.future;
      final dispose = api.dispose();
      gate.complete();
      await Future.wait([shutdown, dispose]);
      expect(provider.stopped, 1);
      expect(() => api.registerProvider(ProbeProvider()), throwsStateError);
    },
  );

  test(
    '1.6.2: late replacement cleanup errors do not enter the reset event stream',
    () async {
      final api = isolated();
      final gate = Completer<void>();
      final old = ProbeProvider(failShutdown: true, shutdownGate: gate);
      await api.setProviderAndWait(old);
      final replace = api.setProviderAndWait(
        ProbeProvider(label: 'replacement'),
      );
      await old.stopping.future;
      final shutdown = api.shutdown();
      final expectedFailure = expectLater(shutdown, throwsStateError);
      final events = <OpenFeatureEvent>[];
      final subscription = api.events.listen(events.add);
      gate.complete();
      await Future.wait([expectedFailure, replace]);
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => identical(event.provider, old)), isEmpty);
      await subscription.cancel();
    },
  );

  test(
    '1.8.4: failed registration validation does not claim the provider',
    () async {
      final first = isolated();
      final second = isolated();
      final provider = ProbeProvider();
      expect(
        () => first.registerProvider(provider, providerId: ''),
        throwsArgumentError,
      );
      await second.setProviderAndWait(provider);
    },
  );

  test(
    '1.6.1: shutdown visits all provider identities once, even uninitialized registrations',
    () async {
      final api = isolated();
      final shared = ProbeProvider();
      final uninitialized = ProbeProvider(label: 'uninitialized');
      await api.setProviderAndWait(shared);
      await api.setProviderForDomainAndWait('one', shared, providerId: 'alias');
      await api.setProviderForDomainAndWait('two', shared, providerId: 'alias');
      api.registerProvider(uninitialized);
      await api.shutdown();
      expect(shared.stopped, 1);
      expect(uninitialized.initialized, 0);
      expect(uninitialized.stopped, 1);
      await api.shutdown();
      expect(shared.stopped, 1);
      expect(uninitialized.stopped, 1);
    },
  );

  test(
    '1.6.2: reset clears context, bindings and API hooks, reusing existing clients',
    () async {
      final api = isolated();
      final provider = ProbeProvider();
      final hook = CountingHook();
      api.addHooks([hook]);
      api.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'old': true}),
      );
      await api.setProviderForDomainAndWait('domain', provider);
      final client = api.getClient('client', domain: 'domain');
      expect(await client.getBooleanFlag('flag'), isTrue);
      expect(hook.calls, 1);
      await api.shutdown();
      expect(api.evaluationContext, isNull);
      expect(api.hooks, isEmpty);
      expect(await client.getBooleanFlag('flag', defaultValue: false), isFalse);
      expect(
        await client.getBooleanFlag('missing', defaultValue: true),
        isTrue,
      );
      expect(hook.calls, 1);
      final next = ProbeProvider(label: 'next');
      await api.setProviderAndWait(next);
      expect(await client.getBooleanFlag('flag'), isTrue);
      expect(next.context, isEmpty);
      await client.dispose();
    },
  );

  test(
    '1.6.2: reset removes typed handlers and paused legacy listeners without blocking',
    () async {
      final api = isolated();
      final client = api.getClient('client');
      var calls = 0;
      void ready(OpenFeatureEvent _) => calls++;
      api.addEventHandler(OpenFeatureEventType.PROVIDER_READY, ready);
      client.addEventHandler(OpenFeatureEventType.PROVIDER_READY, ready);
      final legacy = client.events.listen((_) => calls++);
      legacy.pause();
      await api.setProviderAndWait(ProbeProvider());
      final before = calls;
      await api.shutdown().timeout(const Duration(seconds: 1));
      await api.setProviderAndWait(ProbeProvider());
      legacy.resume();
      await Future<void>.delayed(Duration.zero);
      expect(calls, before);
      client.addEventHandler(OpenFeatureEventType.PROVIDER_READY, ready);
      expect(calls, before + 1);
      await legacy.cancel();
      await client.dispose();
    },
  );

  test(
    '1.6.1: concurrent shutdowns share cleanup and partial failure leaves reusable API',
    () async {
      final api = isolated();
      final gate = Completer<void>();
      final broken = ProbeProvider(failShutdown: true, shutdownGate: gate);
      final good = ProbeProvider(label: 'good');
      await api.setProviderAndWait(broken);
      api.registerProvider(good);
      final first = api.shutdown();
      final second = api.shutdown();
      expect(identical(first, second), isTrue);
      final error = expectLater(first, throwsStateError);
      await good.stopping.future;
      expect(broken.stopped, 1);
      expect(good.stopped, 1);
      expect(() => api.registerProvider(ProbeProvider()), throwsStateError);
      gate.complete();
      await error;
      await api.setProviderAndWait(ProbeProvider());
      expect(await api.getClient('new').getBooleanFlag('flag'), isTrue);
      await api.shutdown();
      expect(broken.stopped, 1);
    },
  );

  for (final domain in [false, true]) {
    test(
      '1.6 / 2.5.2: late ${domain ? 'domain' : 'default'} initialization cannot restore old state',
      () async {
        final api = isolated();
        final gate = Completer<void>();
        final old = EventProbe(initializeGate: gate);
        addTearDown(old.controller.close);
        final binding = domain
            ? api.setProviderForDomainAndWait('domain', old)
            : api.setProviderAndWait(old);
        final canceled = expectLater(binding, throwsStateError);
        await old.entered.future;
        await api.shutdown().timeout(const Duration(seconds: 1));
        expect(old.stopped, 1);
        final fresh = ProbeProvider(label: 'fresh');
        await api.setProviderAndWait(fresh);
        var events = 0;
        api.addEventHandler(
          OpenFeatureEventType.PROVIDER_STALE,
          (_) => events++,
        );
        gate.complete();
        await canceled;
        old.emit(OpenFeatureEventType.PROVIDER_STALE);
        expect(api.provider, same(fresh));
        expect(api.getClient('domain').provider, same(fresh));
        expect(events, 0);
      },
    );
  }

  test(
    '1.8.1-3: factory isolates providers/context/hooks/events from peers and singleton',
    () async {
      final global = OpenFeatureAPI();
      final first = isolated();
      final second = isolated();
      final a = EventProbe();
      final b = EventProbe();
      addTearDown(a.controller.close);
      addTearDown(b.controller.close);
      expect(identical(OpenFeatureAPI(), global), isTrue);
      expect(identical(first, second), isFalse);
      final hook = CountingHook();
      first.addHooks([hook]);
      first.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'api': 'one'}),
      );
      second.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'api': 'two'}),
      );
      await first.setProviderAndWait(a);
      await second.setProviderAndWait(b);
      var firstEvents = 0;
      var secondEvents = 0;
      first.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => firstEvents++,
      );
      second.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => secondEvents++,
      );
      await first.getClient('one').getBooleanFlag('flag');
      await second.getClient('two').getBooleanFlag('flag');
      expect(a.context!['api'], 'one');
      expect(b.context!['api'], 'two');
      expect(hook.calls, 1);
      a.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect([firstEvents, secondEvents], [1, 0]);
      await first.shutdown();
      expect(a.stopped, 1);
      expect(b.stopped, 0);
      expect(await second.getClient('two').getBooleanFlag('flag'), isTrue);
      expect(global.evaluationContext, isNull);
      expect(await global.getClient('global').getBooleanFlag('flag'), isFalse);
    },
  );

  test(
    '1.8.4: shared provider rejected across instances and reusable after shutdown',
    () async {
      final first = isolated();
      final second = isolated();
      final provider = ProbeProvider();
      await first.setProviderAndWait(provider);
      await expectLater(second.setProviderAndWait(provider), throwsStateError);
      expect(provider.initialized, 1);
      expect(first.provider, same(provider));
      await first.shutdown();
      await second.setProviderAndWait(provider);
      expect(provider.initialized, 2);
      expect(provider.stopped, 1);
    },
  );

  test(
    '1.8.4: unfinished old initialization reserves its object until settling',
    () async {
      final first = isolated();
      final second = isolated();
      final gate = Completer<void>();
      final provider = ProbeProvider(initializeGate: gate);
      final binding = first.setProviderAndWait(provider);
      final canceled = expectLater(binding, throwsStateError);
      await provider.entered.future;
      await first.shutdown();
      expect(() => second.registerProvider(provider), throwsStateError);
      expect(() => first.registerProvider(provider), throwsStateError);
      gate.complete();
      await canceled;
      await Future<void>.delayed(Duration.zero);
      await second.setProviderAndWait(provider);
    },
  );

  test(
    '1.8.1 / 1.6.2: transactions isolate instances and reset invalidates old async zones',
    () async {
      final first = isolated();
      final second = isolated();
      final global = OpenFeatureAPI();
      expect(
        identical(
          global.transactionContextManager,
          TransactionContextManager(),
        ),
        isTrue,
      );
      final a = ProbeProvider();
      final b = ProbeProvider();
      await first.setProviderAndWait(a);
      await second.setProviderAndWait(b);
      final firstClient = first.getClient('one');
      final entered = Completer<void>();
      final gate = Completer<void>();
      final operation = first.transactionContextManager.withContext(
        'request',
        {'private': 'one'},
        () async {
          await firstClient.getBooleanFlag('flag');
          expect(a.context!['private'], 'one');
          await second.getClient('two').getBooleanFlag('flag');
          expect(b.context!.containsKey('private'), isFalse);
          entered.complete();
          await gate.future;
          expect(first.transactionContextManager.currentContext, isNull);
          await firstClient.getBooleanFlag('flag');
          expect(a.context!.containsKey('private'), isFalse);
        },
      );
      await entered.future;
      await first.shutdown();
      await first.setProviderAndWait(a);
      gate.complete();
      await operation;
      await firstClient.dispose();
    },
  );

  test(
    'isolated factory does not change process logging configuration',
    () async {
      final previous = Logger.root.level;
      Logger.root.level = Level.WARNING;
      isolated();
      expect(Logger.root.level, Level.WARNING);
      Logger.root.level = previous;
    },
  );

  test(
    'dispose permanently closes the API and performs provider cleanup once',
    () async {
      final api = isolated();
      final provider = ProbeProvider();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      await api.dispose();
      await api.dispose();
      await api.shutdown();
      expect(provider.stopped, 1);
      expect(client.providerStatus, ProviderState.NOT_READY);
      expect(await client.getBooleanFlag('flag', defaultValue: false), isFalse);
      expect(() => api.registerProvider(ProbeProvider()), throwsStateError);
      await client.dispose();
    },
  );
}
