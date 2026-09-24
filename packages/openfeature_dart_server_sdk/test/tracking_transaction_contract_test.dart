import 'dart:async';

import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/experimental/transaction_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/provider_capabilities.dart';
import 'package:openfeature_dart_server_sdk/transaction_context.dart';
import 'package:test/test.dart';

class Resolver implements Provider {
  final contexts = <Map<String, dynamic>>[];
  @override
  ProviderMetadata get metadata => const ProviderMetadata(name: 'resolver');
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
    bool value, {
    Map<String, dynamic>? context,
  }) async {
    contexts.add(context ?? {});
    return result(key, true);
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String key,
    String value, {
    Map<String, dynamic>? context,
  }) async => result(key, value);
  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String key,
    int value, {
    Map<String, dynamic>? context,
  }) async => result(key, value);
  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String key,
    double value, {
    Map<String, dynamic>? context,
  }) async => result(key, value);
  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String key,
    Map<String, dynamic> value, {
    Map<String, dynamic>? context,
  }) async => result(key, value);
}

class TrackingResolver extends Resolver
    implements ProviderTracking, ProviderShutdown {
  final events =
      <
        ({
          String name,
          Map<String, dynamic> context,
          TrackingEventDetails? details,
        })
      >[];
  Completer<void>? gate;
  bool failSync = false;
  bool failAsync = false;
  int shutdowns = 0;
  @override
  Future<void> trackEvent(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) {
    if (failSync) throw StateError('tracking sync failure');
    events.add((
      name: name,
      context: evaluationContext ?? {},
      details: trackingDetails,
    ));
    return finish();
  }

  Future<void> finish() async {
    if (gate != null) await gate!.future;
    if (failAsync) throw StateError('tracking async failure');
  }

  @override
  Future<void> shutdownProvider() async {
    shutdowns++;
    // A provider-owned drain policy, not an SDK-imposed transport protocol.
    if (gate != null) await gate!.future;
  }
}

class LegacyTracker extends InMemoryProvider {
  TrackingEventDetails? details;
  LegacyTracker() : super({});
  @override
  Future<void> track(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    details = trackingDetails;
  }
}

class CustomCarrier implements TransactionContextPropagator {
  final delegate = ZoneTransactionContextPropagator();
  int writes = 0;
  int reads = 0;
  bool failRead = false;
  @override
  EvaluationContext? getTransactionContext() {
    reads++;
    if (failRead) throw StateError('carrier failed');
    return delegate.getTransactionContext();
  }

  @override
  Future<T> setTransactionContext<T>(
    EvaluationContext context,
    FutureOr<T> Function() operation,
  ) {
    writes++;
    return delegate.setTransactionContext(context, operation);
  }
}

void main() {
  late OpenFeatureAPI api;
  late TrackingResolver provider;
  late FeatureClient client;
  setUp(() async {
    api = createIsolatedOpenFeatureAPI();
    provider = TrackingResolver();
    await api.setProviderAndWait(provider);
    client = api.getClient('checkout');
  });
  tearDown(() async => api.dispose());

  test(
    '3.3.1.2.1-3 custom carrier receives context and participates in both APIs',
    () async {
      final carrier = CustomCarrier();
      api.setTransactionContextPropagator(carrier);
      await api.setTransactionContext(
        EvaluationContext.immutable(targetingKey: 'custom'),
        () async {
          await client.track('custom');
          expect(
            await client.getBooleanValue('flag', defaultValue: false),
            isTrue,
          );
        },
      );
      expect(carrier.writes, 1);
      expect(carrier.reads, 2);
      expect(provider.events.single.context['targetingKey'], 'custom');
      expect(provider.contexts.single['targetingKey'], 'custom');
      carrier.failRead = true;
      await expectLater(client.track('failed carrier'), completes);
      expect(provider.events.length, 1);
      expect(
        await client.getBooleanValue('flag', defaultValue: false),
        isFalse,
      );
    },
  );

  test(
    '3.3 explicit carrier takes precedence over legacy transaction context',
    () async {
      await api.transactionContextManager.withContext(
        'legacy',
        {'targetingKey': 'legacy'},
        () async {
          await client.track('legacy');
          api.setTransactionContextPropagator(
            ZoneTransactionContextPropagator(),
          );
          await client.track('empty explicit carrier');
          await api.setTransactionContext(
            EvaluationContext.immutable(targetingKey: 'explicit'),
            () => client.track('explicit'),
          );
          api.setTransactionContextPropagator(null);
          await client.track('legacy restored');
        },
      );
      expect(provider.events.map((e) => e.context['targetingKey']), [
        'legacy',
        null,
        'explicit',
        'legacy',
      ]);
    },
  );

  test(
    '6.1.1.1 / 6.2.1 integer, double and omitted values reach optional tracking',
    () async {
      const integer = TrackingEventDetails(value: 9007199254740993);
      await client.track('integer', trackingDetails: integer);
      await client.track(
        'double',
        trackingDetails: const TrackingEventDetails(value: 1.25),
      );
      await client.track('absent');
      expect(provider.events.map((e) => e.details?.value), [
        9007199254740993,
        1.25,
        null,
      ]);
      expect(provider.events.first.details!.value, isA<int>());
    },
  );

  test(
    '6.2.2 immutable details validate structures and retain nested snapshots',
    () {
      final nested = <String, dynamic>{
        'items': [true, 'sku', 3, null],
      };
      final details = TrackingEventDetails.immutable(
        attributes: {
          'cart': nested,
          'currency': 'USD',
          'member': true,
          'count': 2,
        },
      );
      (nested['items'] as List).clear();
      expect((details.attributes['cart'] as Map)['items'], [
        true,
        'sku',
        3,
        null,
      ]);
      expect(() => details.attributes['extra'] = 1, throwsUnsupportedError);
      expect(
        () => ((details.attributes['cart'] as Map)['items'] as List).clear(),
        throwsUnsupportedError,
      );
      for (final invalid in [
        Object(),
        DateTime(2026),
        null,
        {1: 'bad key'},
      ]) {
        expect(
          () =>
              TrackingEventDetails.immutable(attributes: {'invalid': invalid}),
          throwsArgumentError,
        );
      }
      final cycle = <dynamic>[];
      cycle.add(cycle);
      expect(
        () => TrackingEventDetails.immutable(attributes: {'cycle': cycle}),
        throwsArgumentError,
      );
    },
  );

  test(
    '6.1.3 / 3.2.3 tracking and evaluation share all context levels and targeting keys',
    () async {
      api.setEvaluationContext(
        EvaluationContext.immutable(
          targetingKey: 'api',
          attributes: {'shared': 'api', 'api': true},
        ),
      );
      api.setTransactionContextPropagator(ZoneTransactionContextPropagator());
      final scoped = FeatureClient(
        metadata: ClientMetadata(name: 'checkout'),
        hookManager: HookManager(),
        defaultContext: EvaluationContext.immutable(
          targetingKey: 'client',
          attributes: {'shared': 'client', 'client': true},
        ),
        apiContext: EvaluationContext.immutable(
          targetingKey: 'api',
          attributes: {'shared': 'api', 'api': true},
        ),
        provider: client.provider,
        transactionManager: api.transactionContextManager,
      );
      addTearDown(scoped.dispose);
      await api.setTransactionContext(
        EvaluationContext.immutable(
          targetingKey: 'transaction',
          attributes: {'shared': 'transaction', 'transaction': true},
        ),
        () async {
          final invocation = EvaluationContext.immutable(
            targetingKey: 'invocation',
            attributes: {'shared': 'invocation', 'invocation': true},
          );
          await scoped.track('order', context: invocation);
          await scoped.getBooleanValue(
            'flag',
            defaultValue: false,
            context: invocation,
          );
          expect(provider.events.single.context, {
            'targetingKey': 'invocation',
            'shared': 'invocation',
            'api': true,
            'transaction': true,
            'client': true,
            'invocation': true,
          });
          expect(provider.contexts.single, provider.events.single.context);
          await scoped.track('client');
          expect(provider.events.last.context['targetingKey'], 'client');
          await client.track('transaction');
          expect(provider.events.last.context['targetingKey'], 'transaction');
        },
      );
      await client.track('global');
      expect(provider.events.last.context['targetingKey'], 'api');
    },
  );

  test('6.1.4 resolver-only provider has no tracking requirement', () async {
    await api.setProviderAndWait(Resolver());
    client.trackEvent('ignored');
    await client.track('also ignored');
    expect(await client.getBooleanValue('flag', defaultValue: false), isTrue);
  });

  test(
    '6.1.1.1 nonblocking call contains sync and delayed transport errors',
    () async {
      final messages = <Object>[];
      await runZonedGuarded(() async {
        provider.failSync = true;
        client.trackEvent('sync');
        provider.failSync = false;
        provider.failAsync = true;
        provider.gate = Completer<void>();
        client.trackEvent('async');
        expect(provider.events.single.name, 'async');
        expect(
          await client.getBooleanValue('flag', defaultValue: false),
          isTrue,
        );
        provider.gate!.complete();
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) => messages.add(error));
      expect(messages, isEmpty);
    },
  );

  test(
    '2.7.1 / 2.5 provider owns draining pending tracking on shutdown',
    () async {
      provider.gate = Completer<void>();
      client.trackEvent('pending');
      var done = false;
      final shutdown = api.shutdown().then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(provider.shutdowns, 1);
      expect(done, isFalse);
      provider.gate!.complete();
      await shutdown;
      expect(done, isTrue);
      client.trackEvent('after reset');
      expect(provider.events.length, 1);
    },
  );

  test(
    'legacy tracking keeps const details and opaque attribute identity',
    () async {
      final legacy = LegacyTracker();
      await api.setProviderAndWait(legacy);
      final opaque = Object();
      final attributes = <String, dynamic>{'opaque': opaque};
      final details = TrackingEventDetails(value: 1.5, attributes: attributes);
      await client.track('legacy', trackingDetails: details);
      expect(legacy.details, same(details));
      expect(legacy.details!.attributes, same(attributes));
      expect(legacy.details!.attributes['opaque'], same(opaque));
    },
  );

  test(
    '3.3.1.2.1 missing propagator ignores supplied context and still runs operation',
    () async {
      expect(
        await api.setTransactionContext(
          EvaluationContext.immutable(targetingKey: 'ignored'),
          () async {
            await client.track('missing');
            return 42;
          },
        ),
        42,
      );
      expect(provider.events.single.context, isEmpty);
    },
  );

  test(
    '3.3.1.2.2-3 nested scopes restore parent on success and exceptions',
    () async {
      api.setTransactionContextPropagator(ZoneTransactionContextPropagator());
      await api.setTransactionContext(
        EvaluationContext.immutable(targetingKey: 'parent'),
        () async {
          await expectLater(
            api.setTransactionContext(
              EvaluationContext.immutable(targetingKey: 'child'),
              () async {
                await Future<void>.delayed(Duration.zero);
                await client.track('child');
                throw StateError('application failure');
              },
            ),
            throwsStateError,
          );
          await client.track('parent');
        },
      );
      await client.track('outside');
      expect(provider.events.map((e) => e.context['targetingKey']), [
        'child',
        'parent',
        null,
      ]);
    },
  );

  test(
    '3.3 overlapping async requests never share targeting context',
    () async {
      api.setTransactionContextPropagator(ZoneTransactionContextPropagator());
      final a = Completer<void>();
      final b = Completer<void>();
      await Future.wait([
        api.setTransactionContext(
          EvaluationContext.immutable(targetingKey: 'a'),
          () async {
            a.complete();
            await b.future;
            await client.track('a');
          },
        ),
        api.setTransactionContext(
          EvaluationContext.immutable(targetingKey: 'b'),
          () async {
            await a.future;
            await client.track('b');
            b.complete();
          },
        ),
      ]);
      expect(
        provider.events.map((e) => '${e.name}:${e.context['targetingKey']}'),
        ['b:b', 'a:a'],
      );
      expect(api.transactionContextManager.effectiveContext, isEmpty);
    },
  );

  test(
    '3.3.1.1 replacement/removal invalidates old scopes even for the same carrier',
    () async {
      final carrier = ZoneTransactionContextPropagator();
      api.setTransactionContextPropagator(carrier);
      await api.setTransactionContext(
        EvaluationContext.immutable(targetingKey: 'old'),
        () async {
          api.setTransactionContextPropagator(carrier);
          await client.track('replaced');
          await api.setTransactionContext(
            EvaluationContext.immutable(targetingKey: 'new'),
            () async {
              await client.track('new');
              api.setTransactionContextPropagator(null);
              await client.track('removed');
            },
          );
        },
      );
      expect(provider.events.map((e) => e.context['targetingKey']), [
        null,
        'new',
        null,
      ]);
    },
  );

  test(
    '1.6 / 3.3 shutdown removes carrier and old async scope while peer remains active',
    () async {
      final peer = createIsolatedOpenFeatureAPI();
      addTearDown(peer.dispose);
      final peerProvider = TrackingResolver();
      await peer.setProviderAndWait(peerProvider);
      final carrier = ZoneTransactionContextPropagator();
      api.setTransactionContextPropagator(carrier);
      peer.setTransactionContextPropagator(ZoneTransactionContextPropagator());
      await peer.setTransactionContext(
        EvaluationContext.immutable(targetingKey: 'peer'),
        () async {
          await api.setTransactionContext(
            EvaluationContext.immutable(targetingKey: 'old'),
            () async {
              await api.shutdown();
              provider = TrackingResolver();
              await api.setProviderAndWait(provider);
              await client.track('reset');
              await api.setTransactionContext(
                EvaluationContext.immutable(targetingKey: 'ignored'),
                () => client.track('no carrier'),
              );
              api.setTransactionContextPropagator(carrier);
              await client.track('old carrier');
              await peer.getClient('peer').track('peer');
            },
          );
        },
      );
      expect(provider.events.every((e) => e.context.isEmpty), isTrue);
      expect(peerProvider.events.single.context['targetingKey'], 'peer');
    },
  );

  test('3.3 canonical context is captured before async work', () async {
    api.setTransactionContextPropagator(ZoneTransactionContextPropagator());
    final attributes = <String, dynamic>{
      'nested': <String, dynamic>{'value': 'before'},
    };
    final gate = Completer<void>();
    final operation = api.setTransactionContext(
      EvaluationContext(targetingKey: 'subject', attributes: attributes),
      () async {
        await gate.future;
        await client.track('snapshot');
      },
    );
    (attributes['nested'] as Map)['value'] = 'after';
    gate.complete();
    await operation;
    expect(provider.events.single.context['nested'], {'value': 'before'});
  });

  test(
    '3.3 legacy nested duplicate transaction IDs restore the outer frame',
    () async {
      final manager = api.transactionContextManager;
      await manager.withContext(
        'same',
        {'outer': true, 'shared': 'outer'},
        () async {
          await manager.withContext(
            'same',
            {'inner': true, 'shared': 'inner'},
            () async {
              await client.track('inner');
            },
          );
          await client.track('outer');
        },
      );
      expect(provider.events.first.context, {
        'outer': true,
        'inner': true,
        'shared': 'inner',
      });
      expect(provider.events.last.context, {'outer': true, 'shared': 'outer'});
      expect(manager.currentContext, isNull);
    },
  );

  test(
    '3.3 legacy duplicate IDs pushed in one scope remove only the newest frame',
    () {
      final manager = api.transactionContextManager;
      final first = TransactionContext(
        transactionId: 'same',
        attributes: {'first': true},
      );
      manager.pushContext(first);
      manager.pushContext(
        TransactionContext(transactionId: 'same', attributes: {'second': true}),
      );
      manager.clearContext('same');
      expect(manager.currentContext, same(first));
      expect(manager.popContext(), same(first));
    },
  );
}
