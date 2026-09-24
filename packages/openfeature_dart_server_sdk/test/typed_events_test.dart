import 'dart:async';

import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:test/test.dart';

class EventProvider extends InMemoryProvider implements ProviderEventSource {
  final controller = StreamController<ProviderLifecycleEvent>.broadcast(
    sync: true,
  );
  EventProvider() : super({});

  @override
  Stream<ProviderLifecycleEvent> get providerEvents => controller.stream;

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    await super.initialize(config);
    emit(OpenFeatureEventType.PROVIDER_READY);
  }

  void emit(OpenFeatureEventType type, {ErrorCode? errorCode}) =>
      controller.add(
        ProviderLifecycleEvent(
          type,
          'provider message',
          errorCode: errorCode,
          flagsChanged: ['flag'],
          eventMetadata: {'revision': 2},
        ),
      );
}

void main() {
  late OpenFeatureAPI api;
  final providers = <EventProvider>[];
  EventProvider create() {
    final provider = EventProvider();
    providers.add(provider);
    return provider;
  }

  setUp(() => api = OpenFeatureAPI());
  tearDown(() async {
    await OpenFeatureAPI.resetInstance();
    for (final provider in providers) {
      await provider.controller.close();
    }
    providers.clear();
  });

  test(
    '5.3.3: registration inside another handler replays state once',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      var calls = 0;
      void late(OpenFeatureEvent _) => calls++;
      api.addEventHandler(OpenFeatureEventType.PROVIDER_STALE, (_) {
        client.addEventHandler(OpenFeatureEventType.PROVIDER_STALE, late);
      });
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect(calls, 1);
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect(calls, 2);
      await client.dispose();
    },
  );

  test(
    '5.2.6: pending default replacement preserves events from active provider',
    () async {
      final first = create();
      final gate = Completer<void>();
      final second = GatedProvider(gate);
      providers.add(second);
      await api.setProviderAndWait(first);
      final client = api.getClient('client');
      final events = <OpenFeatureEvent>[];
      client.addEventHandler(OpenFeatureEventType.PROVIDER_STALE, events.add);
      final replacement = api.setProviderAndWait(second);
      await second.entered.future;
      first.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect(events.single.provider, same(first));
      gate.complete();
      await replacement;
      first.emit(OpenFeatureEventType.PROVIDER_STALE);
      second.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect(events.map((event) => event.provider), [first, second]);
      await client.dispose();
    },
  );

  test(
    '5.3.2: failed default initialization reaches existing client error handler',
    () async {
      final provider = FailedProvider();
      providers.add(provider);
      final client = api.getClient('client');
      final errors = <OpenFeatureEvent>[];
      client.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, errors.add);
      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<ProviderException>()),
      );
      expect(errors.single.provider, same(provider));
      expect(errors.single.errorCode, ErrorCode.PROVIDER_FATAL);
      expect(client.providerStatus, ProviderState.FATAL);
      await client.dispose();
    },
  );

  test(
    '5.3.1: domain replacement only replays readiness to newly bound domain',
    () async {
      final provider = create();
      await api.setProviderForDomainAndWait('one', provider);
      final one = api.getClient('one');
      final two = api.getClient('two');
      var firstCount = 0;
      var secondCount = 0;
      one.addEventHandler(
        OpenFeatureEventType.PROVIDER_READY,
        (_) => firstCount++,
      );
      two.addEventHandler(
        OpenFeatureEventType.PROVIDER_READY,
        (_) => secondCount++,
      );
      await api.setProviderForDomainAndWait('two', provider);
      expect([firstCount, secondCount], [1, 2]);
      await one.dispose();
      await two.dispose();
    },
  );

  test(
    '5.1.1: lifecycle compatibility names use the canonical event model',
    () {
      final event = ProviderLifecycleEvent(
        ProviderLifecycleEventType.PROVIDER_READY,
        'ready',
      );
      expect(event, isA<OpenFeatureEvent>());
      expect(event.type, OpenFeatureEventType.PROVIDER_READY);
    },
  );

  test(
    '5.2.1-4: typed API/client handlers receive canonical details',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('default');
      final global = <OpenFeatureEvent>[];
      final local = <OpenFeatureEvent>[];
      api.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, global.add);
      client.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, local.add);
      provider.emit(OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED);
      expect(global, isEmpty);
      provider.emit(
        OpenFeatureEventType.PROVIDER_ERROR,
        errorCode: ErrorCode.PROVIDER_FATAL,
      );
      expect(global, hasLength(1));
      expect(local.single, same(global.single));
      expect(local.single.providerName, provider.metadata.name);
      expect(local.single.errorMessage, 'provider message');
      expect(local.single.errorCode, ErrorCode.PROVIDER_FATAL);
      expect(local.single.flagsChanged, ['flag']);
      expect(local.single.eventMetadata, {'revision': 2});
      await client.dispose();
    },
  );

  test(
    '5.1.2-3: same-name instances and default fallback stay isolated',
    () async {
      final first = create();
      final second = create();
      await api.setProviderAndWait(first);
      await api.setProviderForDomainAndWait(
        'second',
        second,
        providerId: 'second',
      );
      final fallback = api.getClient('unbound');
      final bound = api.getClient('second');
      var firstCount = 0;
      var secondCount = 0;
      fallback.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => firstCount++,
      );
      bound.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => secondCount++,
      );
      first.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect([firstCount, secondCount], [1, 0]);
      second.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect([firstCount, secondCount], [1, 1]);
      await fallback.dispose();
      await bound.dispose();
    },
  );

  test(
    '5.1.3: binding notification cannot leak across shared-provider domains',
    () async {
      final provider = create();
      await api.setProviderForDomainAndWait('one', provider);
      final one = api.getClient('one');
      final two = api.getClient('two');
      final first = <OpenFeatureEvent>[];
      final second = <OpenFeatureEvent>[];
      one.addEventHandler(
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
        first.add,
      );
      two.addEventHandler(
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
        second.add,
      );
      await api.setProviderForDomainAndWait('two', provider);
      expect(first, isEmpty);
      expect(second.single.domain, 'two');
      provider.emit(OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED);
      expect(first, hasLength(1));
      expect(second, hasLength(2));
      await one.dispose();
      await two.dispose();
    },
  );

  test(
    '5.2.5: synchronous and async handler failures do not escape or block peers',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      var called = 0;
      api.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => throw StateError('sync'),
      );
      client.addEventHandler(OpenFeatureEventType.PROVIDER_STALE, (_) async {
        await Future<void>.delayed(Duration.zero);
        throw StateError('async');
      });
      client.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => called++,
      );
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(called, 1);
      await client.dispose();
    },
  );

  test(
    '5.2.6 / 5.3.1: existing client receives readiness after provider binding',
    () async {
      final first = create();
      final second = create();
      final client = api.getClient('client');
      final events = <OpenFeatureEvent>[];
      client.addEventHandler(OpenFeatureEventType.PROVIDER_READY, events.add);
      events.clear(); // Initial no-op provider is already ready.
      await api.setProviderAndWait(first);
      await api.setProviderAndWait(second);
      expect(events.map((event) => event.provider), [first, second]);
      first.emit(OpenFeatureEventType.PROVIDER_READY);
      expect(events, hasLength(2));
      await client.dispose();
    },
  );

  test('5.2.7: removal and self-removal preserve other handlers', () async {
    final provider = create();
    await api.setProviderAndWait(provider);
    final client = api.getClient('client');
    var apiCount = 0;
    var selfCount = 0;
    var otherCount = 0;
    void global(OpenFeatureEvent _) => apiCount++;
    void self(OpenFeatureEvent _) {
      selfCount++;
      client.removeEventHandler(
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
        self,
      );
    }

    api.addEventHandler(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      global,
    );
    client.addEventHandler(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      self,
    );
    client.addEventHandler(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      (_) => otherCount++,
    );
    provider.emit(OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED);
    api.removeEventHandler(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      global,
    );
    provider.emit(OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED);
    expect([apiCount, selfCount, otherCount], [1, 1, 2]);
    await client.dispose();
  });

  test(
    '5.3.3: late readiness/error/stale handlers run immediately only in matching state',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      var ready = 0;
      var stale = 0;
      client.addEventHandler(
        OpenFeatureEventType.PROVIDER_READY,
        (_) => ready++,
      );
      expect(ready, 1);
      client.addEventHandler(
        OpenFeatureEventType.PROVIDER_STALE,
        (_) => stale++,
      );
      expect(stale, 0);
      provider.emit(
        OpenFeatureEventType.PROVIDER_ERROR,
        errorCode: ErrorCode.PROVIDER_FATAL,
      );
      final errors = <OpenFeatureEvent>[];
      client.addEventHandler(OpenFeatureEventType.PROVIDER_ERROR, errors.add);
      expect(errors.single.errorCode, ErrorCode.PROVIDER_FATAL);
      expect(errors.single.message, 'provider message');
      client.addEventHandler(
        OpenFeatureEventType.PROVIDER_READY,
        (_) => ready++,
      );
      expect(ready, 1);
      await client.dispose();
    },
  );

  test(
    '5.3.3: API late registration visits each registered instance once',
    () async {
      final first = create();
      final second = create();
      await api.setProviderAndWait(first);
      await api.setProviderForDomainAndWait('one', first, providerId: 'alias');
      await api.setProviderForDomainAndWait(
        'two',
        second,
        providerId: 'second',
      );
      final events = <OpenFeatureEvent>[];
      api.addEventHandler(OpenFeatureEventType.PROVIDER_READY, events.add);
      expect(events.where((e) => identical(e.provider, first)), hasLength(1));
      expect(events.where((e) => identical(e.provider, second)), hasLength(1));
    },
  );

  test(
    '5.3.5: sequential events expose their own updated state in handlers',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      final states = <ProviderState>[];
      for (final type in [
        OpenFeatureEventType.PROVIDER_STALE,
        OpenFeatureEventType.PROVIDER_ERROR,
      ]) {
        client.addEventHandler(type, (_) => states.add(client.providerStatus));
      }
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      provider.emit(
        OpenFeatureEventType.PROVIDER_ERROR,
        errorCode: ErrorCode.PROVIDER_FATAL,
      );
      expect(states, [ProviderState.STALE, ProviderState.FATAL]);
      await client.dispose();
    },
  );

  test(
    'compatibility streams share routing and client disposal cancels typed handlers',
    () async {
      final provider = create();
      await api.setProviderAndWait(provider);
      final client = api.getClient('client');
      final stream = <OpenFeatureEvent>[];
      final typed = <OpenFeatureEvent>[];
      final sub = client.events.listen(stream.add);
      client.addEventHandler(OpenFeatureEventType.PROVIDER_STALE, typed.add);
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      await Future<void>.delayed(Duration.zero);
      expect(stream.single, same(typed.single));
      await sub.cancel();
      await client.dispose();
      provider.emit(OpenFeatureEventType.PROVIDER_STALE);
      expect(typed, hasLength(1));
    },
  );

  test('event detail collections cannot be changed by callers or handlers', () {
    final flags = ['flag'];
    final metadata = <String, Object>{'revision': 1};
    final event = ProviderLifecycleEvent(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      'changed',
      flagsChanged: flags,
      eventMetadata: metadata,
    );
    flags.clear();
    metadata.clear();
    expect(event.flagsChanged, ['flag']);
    expect(event.eventMetadata, {'revision': 1});
    expect(() => event.flagsChanged!.clear(), throwsUnsupportedError);
    expect(() => event.eventMetadata.clear(), throwsUnsupportedError);
    expect(
      () => ProviderLifecycleEvent(
        OpenFeatureEventType.PROVIDER_READY,
        '',
        eventMetadata: {'invalid': Object()},
      ),
      throwsArgumentError,
    );
  });
}

class GatedProvider extends EventProvider {
  final Completer<void> gate;
  final entered = Completer<void>();
  GatedProvider(this.gate);
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    entered.complete();
    await gate.future;
    await super.initialize(config);
  }
}

class FailedProvider extends EventProvider {
  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    emit(
      OpenFeatureEventType.PROVIDER_ERROR,
      errorCode: ErrorCode.PROVIDER_FATAL,
    );
    throw const ProviderException('failed', code: ErrorCode.PROVIDER_FATAL);
  }
}
