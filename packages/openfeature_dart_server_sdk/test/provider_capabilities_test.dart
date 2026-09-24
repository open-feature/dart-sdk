import 'dart:async';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/provider_capabilities.dart';
import 'package:openfeature_dart_server_sdk/src/provider_adapter.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:openfeature_dart_server_sdk/src/provider_lifecycle_manager.dart';

// This deliberately implements only metadata and the five typed resolvers.
// No base class supplies hidden lifecycle, tracking, config or connect members.
class MinimalProvider implements Provider {
  final String label;
  final bool boolean;
  final contexts = <Map<String, dynamic>?>[];
  MinimalProvider({this.label = 'minimal', this.boolean = true});
  @override
  ProviderMetadata get metadata => ProviderMetadata(name: label);
  FlagEvaluationResult<T> result<T>(String key, T value) =>
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
  }) async {
    contexts.add(context);
    return result(key, boolean);
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String key,
    String fallback, {
    Map<String, dynamic>? context,
  }) async => result(key, 'resolved');
  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String key,
    int fallback, {
    Map<String, dynamic>? context,
  }) async => result(key, 42);
  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String key,
    double fallback, {
    Map<String, dynamic>? context,
  }) async => result(key, 1.5);
  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String key,
    Map<String, dynamic> fallback, {
    Map<String, dynamic>? context,
  }) async => result(key, {'resolved': true});
}

class LifecycleProvider extends MinimalProvider
    implements ProviderInitialization, ProviderShutdown {
  final StreamController<ProviderLifecycleEvent> controller;
  final Completer<void>? gate;
  final entered = Completer<void>();
  final bool emit;
  final bool fail;
  final bool wrongEvent;
  EvaluationContext? initialContext;
  String? initialDomain;
  int initializations = 0;
  int shutdowns = 0;
  LifecycleProvider({
    this.gate,
    this.emit = true,
    this.fail = false,
    this.wrongEvent = false,
    bool syncEvents = true,
    super.label,
    super.boolean,
  }) : controller = StreamController<ProviderLifecycleEvent>.broadcast(
         sync: syncEvents,
       );
  @override
  Stream<ProviderLifecycleEvent> get providerEvents => controller.stream;
  @override
  Future<void> initializeProvider(
    EvaluationContext context, {
    String? domain,
  }) async {
    initializations++;
    initialContext = context;
    initialDomain = domain;
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    if (emit) {
      controller.add(
        ProviderLifecycleEvent(
          fail && !wrongEvent
              ? ProviderLifecycleEventType.PROVIDER_ERROR
              : ProviderLifecycleEventType.PROVIDER_READY,
          'provider-owned',
          errorCode: fail && !wrongEvent ? ErrorCode.PROVIDER_FATAL : null,
        ),
      );
    }
    if (fail)
      throw const ProviderException(
        'init failed',
        code: ErrorCode.PROVIDER_FATAL,
      );
  }

  @override
  Future<void> shutdownProvider() async {
    shutdowns++;
  }
}

class ScopedProvider extends LifecycleProvider
    implements DomainScopedProvider {}

class InvalidScopedProvider extends MinimalProvider
    implements DomainScopedProvider {}

class RecorderHook extends BaseHook {
  final String label;
  final List<String> calls;
  final bool fail;
  RecorderHook(this.label, this.calls, {this.fail = false})
    : super(metadata: HookMetadata(name: label));
  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    calls.add('$label.before');
    if (fail) throw StateError('before failed');
    return {'lastHook': label};
  }

  @override
  Future<void> after(HookContext context) async {
    calls.add('$label.after');
  }

  @override
  Future<void> error(HookContext context) async {
    calls.add('$label.error');
  }

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? details, [
    HookHints? hints,
  ]) async {
    calls.add('$label.finally');
  }
}

class HookProvider extends MinimalProvider implements ProviderHooks {
  @override
  final List<Hook> hooks;
  HookProvider(this.hooks);
}

class TrackingProvider extends MinimalProvider implements ProviderTracking {
  String? event;
  Map<String, dynamic>? trackingContext;
  TrackingEventDetails? details;
  @override
  Future<void> trackEvent(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    event = name;
    trackingContext = evaluationContext;
    details = trackingDetails;
  }
}

class MigratingLegacyProvider extends InMemoryProvider
    implements ProviderTracking {
  int capabilityCalls = 0;
  int legacyCalls = 0;
  MigratingLegacyProvider() : super({});
  @override
  Future<void> trackEvent(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    capabilityCalls++;
  }

  @override
  Future<void> track(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    legacyCalls++;
  }
}

void main() {
  late OpenFeatureAPI api;
  setUp(() {
    api = OpenFeatureAPI();
  });
  tearDown(OpenFeatureAPI.resetInstance);

  test(
    'legacy providers can opt into tracking without invoking the old stub',
    () async {
      final provider = MigratingLegacyProvider();
      await api.setProviderAndWait(provider);
      final client = api.getClient('migration');
      addTearDown(client.dispose);
      await client.track('event');
      expect(provider.capabilityCalls, 1);
      expect(provider.legacyCalls, 0);
    },
  );

  test(
    '2.8.2: asynchronously delivered events emitted before return are accepted',
    () async {
      final provider = LifecycleProvider(syncEvents: false);
      addTearDown(provider.controller.close);
      await api.setProviderAndWait(provider);
      expect(api.providerStatus, ProviderState.READY);
    },
  );

  test(
    '2.4.1: concurrent bindings keep the first domain and context snapshot',
    () async {
      final gate = Completer<void>();
      final provider = LifecycleProvider(gate: gate);
      addTearDown(provider.controller.close);
      api.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'version': 1}),
      );
      final first = api.setProviderForDomainAndWait('first', provider);
      await provider.entered.future;
      api.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'version': 2}),
      );
      final second = api.setProviderForDomainAndWait('second', provider);
      gate.complete();
      await Future.wait([first, second]);
      expect(provider.initialDomain, 'first');
      expect(provider.initialContext!.attributes['version'], 1);
      expect(provider.initializations, 1);
    },
  );

  test(
    '2.1.1/2.2.1/2.8.5: minimal provider evaluates all types without capabilities',
    () async {
      final provider = MinimalProvider();
      await api.setProviderAndWait(provider);
      final client = api.getClient('minimal');
      addTearDown(client.dispose);
      expect(client.providerStatus, ProviderState.READY);
      expect(await client.getBooleanFlag('b', defaultValue: false), true);
      expect(
        await client.getStringFlag('s', defaultValue: 'fallback'),
        'resolved',
      );
      expect(await client.getIntegerFlag('i', defaultValue: 0), 42);
      expect(await client.getDoubleFlag('d', defaultValue: 0), 1.5);
      expect(await client.getObjectFlag('o', defaultValue: {}), {
        'resolved': true,
      });
      await client.track('unsupported');
      await api.shutdownProvider();
    },
  );

  test(
    '2.4.1: initialization receives immutable global context and default domain',
    () async {
      final original = {'plan': 'standard'};
      api.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'account': original}),
      );
      final provider = LifecycleProvider();
      addTearDown(provider.controller.close);
      original['plan'] = 'premium';
      await api.setProviderAndWait(provider);
      expect(provider.initialDomain, isNull);
      expect(provider.initialContext!.attributes, {
        'account': {'plan': 'standard'},
      });
      expect(
        () =>
            provider.initialContext!.attributes['account']['plan'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );

  test(
    '2.4.1: initialize once with first domain, reuse adapter identity',
    () async {
      final provider = LifecycleProvider();
      addTearDown(provider.controller.close);
      await api.setProviderForDomainAndWait('first', provider);
      final first = api.getClient('first');
      final second = api.getClient('second');
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await api.setProviderForDomainAndWait('second', provider);
      expect(provider.initializations, 1);
      expect(provider.initialDomain, 'first');
      expect(identical(first.provider, second.provider), isTrue);
      expect(
        (first.provider as ResolverProviderAdapter).delegate,
        same(provider),
      );
    },
  );

  test(
    '2.4.3/2.4.4: domain-scoped capability rejects a second domain',
    () async {
      final provider = ScopedProvider();
      addTearDown(provider.controller.close);
      await api.setProviderForDomainAndWait('first', provider);
      await expectLater(
        api.setProviderForDomainAndWait('second', provider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.code,
            'code',
            ErrorCode.INVALID_CONTEXT,
          ),
        ),
      );
      expect(provider.initialDomain, 'first');
      expect(provider.initializations, 1);
    },
  );

  test(
    '2.4.4: domain-scoped declaration requires initialization capability',
    () {
      expect(
        () => api.registerProvider(InvalidScopedProvider()),
        throwsArgumentError,
      );
    },
  );

  test('2.8.2: ready event updates SDK state before the handler', () async {
    final provider = LifecycleProvider();
    final adapter = ResolverProviderAdapter(provider);
    late ProviderLifecycleManager manager;
    final states = <ProviderState>[];
    manager = ProviderLifecycleManager((source, event) {
      expect(source, same(adapter));
      states.add(manager.statusOf(source));
    });
    addTearDown(provider.controller.close);
    addTearDown(manager.dispose);
    await manager.initialize(adapter);
    expect(states, [ProviderState.READY]);
  });

  test(
    '2.8.3: abnormal initialization propagates the provider error and status',
    () async {
      final provider = LifecycleProvider(fail: true);
      addTearDown(provider.controller.close);
      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(
          isA<ProviderException>().having(
            (error) => error.code,
            'code',
            ErrorCode.PROVIDER_FATAL,
          ),
        ),
      );
      expect(api.providerStatus, ProviderState.FATAL);
    },
  );

  test(
    '2.8.2-4: missing event fails without legacy grace; late ready is ignored',
    () async {
      final provider = LifecycleProvider(emit: false);
      final adapter = ResolverProviderAdapter(provider);
      final events = <ProviderLifecycleEvent>[];
      final manager = ProviderLifecycleManager((_, event) => events.add(event));
      addTearDown(provider.controller.close);
      addTearDown(manager.dispose);
      await expectLater(
        manager.initialize(adapter),
        throwsA(isA<ProviderException>()),
      );
      provider.controller.add(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_READY,
          'too late',
        ),
      );
      expect(manager.statusOf(adapter), ProviderState.ERROR);
      expect(events, isEmpty);
    },
  );

  test(
    '2.8.3: ready followed by thrown initialization cannot remain ready',
    () async {
      final provider = LifecycleProvider(fail: true, wrongEvent: true);
      addTearDown(provider.controller.close);
      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<ProviderException>()),
      );
      expect(api.providerStatus, isNot(ProviderState.READY));
    },
  );

  test(
    '2.5: shared provider shuts down once only after its final binding',
    () async {
      final provider = LifecycleProvider();
      final adapter = ResolverProviderAdapter(provider);
      final manager = ProviderLifecycleManager((_, _) {});
      addTearDown(provider.controller.close);
      addTearDown(manager.dispose);
      await manager.initialize(adapter);
      manager.bindDefault(adapter);
      manager.bindDomain(adapter, 'domain');
      await manager.unbindDefault(adapter);
      expect(provider.shutdowns, 0);
      await manager.unbindDomain(adapter, 'domain');
      await adapter.shutdownProvider();
      expect(provider.shutdowns, 1);
      await manager.initialize(adapter);
      manager.bindDefault(adapter);
      await manager.unbindDefault(adapter);
      expect(provider.initializations, 2);
      expect(provider.shutdowns, 2);
    },
  );

  test(
    '2.3.1: optional provider hooks run after client before hooks, reverse on return',
    () async {
      final calls = <String>[];
      final provider = HookProvider([RecorderHook('provider', calls)]);
      await api.setProviderAndWait(provider);
      final client = api.getClient('hooks')
        ..addHook(RecorderHook('client', calls));
      addTearDown(client.dispose);
      expect(await client.getBooleanFlag('flag'), isTrue);
      expect(provider.contexts.single!['lastHook'], 'provider');
      expect(calls, [
        'client.before',
        'provider.before',
        'provider.after',
        'client.after',
        'provider.finally',
        'client.finally',
      ]);
    },
  );

  test(
    '2.3.1: failing provider before hook defaults without provider resolution',
    () async {
      final calls = <String>[];
      final provider = HookProvider([
        RecorderHook('provider', calls, fail: true),
      ]);
      await api.setProviderAndWait(provider);
      final client = api.getClient('hooks')
        ..addHook(RecorderHook('client', calls));
      addTearDown(client.dispose);
      expect(await client.getBooleanFlag('flag', defaultValue: false), isFalse);
      expect(provider.contexts, isEmpty);
      expect(calls, [
        'client.before',
        'provider.before',
        'provider.error',
        'client.error',
        'provider.finally',
        'client.finally',
      ]);
    },
  );

  test(
    '2.7.1: tracking capability receives merged context and details',
    () async {
      final provider = TrackingProvider();
      api.setEvaluationContext(
        EvaluationContext.immutable(attributes: {'source': 'global'}),
      );
      await api.setProviderAndWait(provider);
      final client = api.getClient('tracking');
      addTearDown(client.dispose);
      const details = TrackingEventDetails(
        value: 1.5,
        attributes: {'action': 'arrive'},
      );
      await client.track(
        'arrived',
        context: EvaluationContext.immutable(
          targetingKey: 'rider',
          attributes: {'source': 'invocation'},
        ),
        trackingDetails: details,
      );
      expect(provider.event, 'arrived');
      expect(provider.trackingContext, {
        'source': 'invocation',
        'targetingKey': 'rider',
      });
      expect(provider.details, same(details));
    },
  );

  test(
    'legacy provider identity and behavior are retained without wrapping',
    () async {
      final legacy = InMemoryProvider({'flag': true});
      await api.setProviderAndWait(legacy);
      expect(api.provider, same(legacy));
      final client = api.getClient('legacy');
      addTearDown(client.dispose);
      expect(await client.getBooleanFlag('flag', defaultValue: false), isTrue);
    },
  );

  test(
    '1.1.2/2.4.1: newest replacement wins while earlier initialization waits',
    () async {
      final gate = Completer<void>();
      final first = LifecycleProvider(
        gate: gate,
        label: 'same',
        boolean: false,
      );
      final second = LifecycleProvider(label: 'same', boolean: true);
      addTearDown(first.controller.close);
      addTearDown(second.controller.close);
      final client = api.getClient('existing');
      addTearDown(client.dispose);
      final pending = api.setProviderAndWait(first);
      await first.entered.future;
      await api.setProviderAndWait(second);
      gate.complete();
      await pending;
      expect((api.provider as ResolverProviderAdapter).delegate, same(second));
      expect(await client.getBooleanFlag('flag', defaultValue: false), isTrue);
      expect(first.shutdowns, 1);
    },
  );
}
