import 'dart:async';

import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart'
    show createIsolatedOpenFeatureAPI;
import 'package:test/test.dart';

void main() {
  late OpenFeatureAPI api;

  setUp(() {
    api = createIsolatedOpenFeatureAPI();
  });

  tearDown(() => api.shutdown());

  test('delivers ready after binding and status update', () async {
    final apiEvents = <ProviderEventDetails>[];
    final clientEvents = <ProviderEventDetails>[];
    final client = api.getClient('checkout');
    ProviderStatus? statusDuringHandler;
    api.addHandler(ProviderEventType.ready, apiEvents.add);
    client.addHandler(ProviderEventType.ready, (details) {
      statusDuringHandler = client.providerStatus;
      clientEvents.add(details);
    });

    await api.setProviderForDomainAndWait(
      'checkout',
      _EventProvider(name: 'checkout-provider'),
    );

    expect(statusDuringHandler, ProviderStatus.ready);
    expect(apiEvents, hasLength(1));
    expect(apiEvents.single.providerMetadata.name, 'checkout-provider');
    expect(apiEvents.single.domain, 'checkout');
    expect(clientEvents, hasLength(1));
    expect(clientEvents.single.domain, 'checkout');
  });

  test('keeps associated handlers across provider changes', () async {
    final first = _EventProvider(name: 'first');
    final replacement = _EventProvider(name: 'replacement');
    final apiEvents = <ProviderEventDetails>[];
    final defaultEvents = <ProviderEventDetails>[];
    final fallbackEvents = <ProviderEventDetails>[];
    final domainEvents = <ProviderEventDetails>[];
    api.addHandler(ProviderEventType.configurationChanged, apiEvents.add);
    api.getClient().addHandler(
      ProviderEventType.configurationChanged,
      defaultEvents.add,
    );
    final fallbackClient = api.getClient('fallback');
    final fallbackSubscription = fallbackClient.addHandler(
      ProviderEventType.configurationChanged,
      fallbackEvents.add,
    );
    api
        .getClient('checkout')
        .addHandler(ProviderEventType.configurationChanged, domainEvents.add);
    await api.setProviderAndWait(first);
    await api.setProviderForDomainAndWait(
      'checkout',
      _EventProvider(name: 'domain'),
    );

    first.emit(ProviderEventType.configurationChanged, flagsChanged: ['flag']);
    await api.setProviderAndWait(replacement);
    first.emit(ProviderEventType.configurationChanged);
    replacement.emit(ProviderEventType.configurationChanged);
    fallbackClient.removeHandler(fallbackSubscription);
    replacement.emit(ProviderEventType.configurationChanged);

    expect(apiEvents.map((event) => event.providerMetadata.name), [
      'first',
      'replacement',
      'replacement',
    ]);
    expect(defaultEvents, hasLength(3));
    expect(fallbackEvents, hasLength(2));
    expect(domainEvents, isEmpty);
    expect(fallbackSubscription.isActive, isFalse);
  });

  for (final domain in [null, 'checkout']) {
    for (final sync in [true, false]) {
      test(
        'replays initialization statuses for $domain with sync=$sync',
        () async {
          final client = api.getClient(domain);
          final provider = _InitializingEventProvider(sync: sync);
          final apiStates = <(ProviderEventType, ProviderStatus)>[];
          final clientStates = <(ProviderEventType, ProviderStatus)>[];
          for (final type in [
            ProviderEventType.ready,
            ProviderEventType.configurationChanged,
            ProviderEventType.stale,
          ]) {
            api.addHandler(
              type,
              (_) => apiStates.add((type, client.providerStatus)),
            );
            client.addHandler(
              type,
              (_) => clientStates.add((type, client.providerStatus)),
            );
          }

          if (domain == null) {
            await api.setProviderAndWait(provider);
          } else {
            await api.setProviderForDomainAndWait(domain, provider);
          }

          final expected = [
            (ProviderEventType.configurationChanged, ProviderStatus.notReady),
            (ProviderEventType.ready, ProviderStatus.ready),
            (ProviderEventType.configurationChanged, ProviderStatus.ready),
            (ProviderEventType.stale, ProviderStatus.stale),
          ];
          expect(apiStates, expected);
          expect(clientStates, expected);
          expect(client.providerStatus, ProviderStatus.stale);
          final lateStates = <ProviderStatus>[];
          client.addHandler(
            ProviderEventType.stale,
            (_) => lateStates.add(client.providerStatus),
          );
          expect(lateStates, [ProviderStatus.stale]);
        },
      );
    }

    test(
      'queues handler events behind initialization events for $domain',
      () async {
        final client = api.getClient(domain);
        final provider = _InitializingEventProvider();
        final apiStates = <(ProviderEventType, ProviderStatus)>[];
        final clientStates = <(ProviderEventType, ProviderStatus)>[];
        api.addHandler(ProviderEventType.ready, (_) {
          provider.emit(ProviderEventType.error, errorCode: ErrorCode.general);
        });
        for (final type in [
          ProviderEventType.ready,
          ProviderEventType.stale,
          ProviderEventType.error,
        ]) {
          api.addHandler(
            type,
            (_) => apiStates.add((type, client.providerStatus)),
          );
          client.addHandler(
            type,
            (_) => clientStates.add((type, client.providerStatus)),
          );
        }

        if (domain == null) {
          await api.setProviderAndWait(provider);
        } else {
          await api.setProviderForDomainAndWait(domain, provider);
        }

        final expected = [
          (ProviderEventType.ready, ProviderStatus.ready),
          (ProviderEventType.stale, ProviderStatus.stale),
          (ProviderEventType.error, ProviderStatus.error),
        ];
        expect(apiStates, expected);
        expect(clientStates, expected);
        expect(client.providerStatus, ProviderStatus.error);
      },
    );
  }

  test('contains handler failures and protects event details', () async {
    final provider = _EventProvider();
    final delivered = <ProviderEventDetails>[];
    api.addHandler(ProviderEventType.configurationChanged, (_) {
      throw StateError('handler failed');
    });
    api.addHandler(ProviderEventType.configurationChanged, delivered.add);
    await api.setProviderAndWait(provider);

    expect(
      () => provider.emit(
        ProviderEventType.configurationChanged,
        flagsChanged: ['one'],
        metadata: {'cached': true},
      ),
      returnsNormally,
    );

    final details = delivered.single;
    expect(details.flagsChanged, ['one']);
    expect(details.metadata, {'cached': true});
    expect(() => details.flagsChanged.add('two'), throwsUnsupportedError);
    expect(() => details.metadata['new'] = true, throwsUnsupportedError);
  });

  test('late handlers receive the current lifecycle state', () async {
    final provider = _EventProvider();
    await api.setProviderAndWait(provider);
    final readyEvents = <ProviderEventDetails>[];

    api.getClient().addHandler(ProviderEventType.ready, readyEvents.add);
    provider.emit(ProviderEventType.stale);
    final staleEvents = <ProviderEventDetails>[];
    api.getClient().addHandler(ProviderEventType.stale, staleEvents.add);
    provider.emit(
      ProviderEventType.error,
      errorCode: ErrorCode.invalidContext,
      message: 'invalid targeting key',
      metadata: {'retryable': false},
    );
    final errorEvents = <ProviderEventDetails>[];
    api.getClient().addHandler(ProviderEventType.error, errorEvents.add);

    expect(readyEvents, hasLength(1));
    expect(staleEvents, hasLength(1));
    expect(api.getClient().providerStatus, ProviderStatus.error);
    expect(errorEvents.single.errorCode, ErrorCode.invalidContext);
    expect(errorEvents.single.message, 'invalid targeting key');
    expect(errorEvents.single.metadata, {'retryable': false});
  });

  test('removal is idempotent and shutdown resets handlers', () async {
    final events = <ProviderEventDetails>[];
    final subscription = api.addHandler(
      ProviderEventType.configurationChanged,
      events.add,
    );
    final provider = _EventProvider();
    await api.setProviderAndWait(provider);

    subscription.cancel();
    subscription.cancel();
    provider.emit(ProviderEventType.configurationChanged);
    expect(events, isEmpty);

    final active = api.addHandler(
      ProviderEventType.configurationChanged,
      events.add,
    );
    expect(active.isActive, isTrue);
    await api.shutdown();
    expect(active.isActive, isFalse);
  });
}

final class _EventProvider implements FeatureProvider, ProviderEventSource {
  _EventProvider({this.name = 'event-provider', bool sync = true})
    : _delegate = InMemoryProvider({'flag': true}),
      _events = StreamController<ProviderEvent>.broadcast(sync: sync);

  final String name;
  final InMemoryProvider _delegate;
  final StreamController<ProviderEvent> _events;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  ProviderMetadata get metadata => ProviderMetadata(name: name);

  void emit(
    ProviderEventType type, {
    Iterable<String> flagsChanged = const [],
    String? message,
    ErrorCode? errorCode,
    Map<String, Object> metadata = const {},
  }) {
    _events.add(
      ProviderEvent(
        type: type,
        flagsChanged: flagsChanged,
        message: message,
        errorCode: errorCode,
        metadata: metadata,
      ),
    );
  }

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

final class _InitializingEventProvider extends _EventProvider
    implements InitializableProvider, ShutdownProvider {
  _InitializingEventProvider({super.sync});

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    final delivered = events.firstWhere(
      (event) => event.type == ProviderEventType.stale,
    );
    emit(ProviderEventType.configurationChanged);
    emit(ProviderEventType.ready);
    emit(ProviderEventType.configurationChanged);
    emit(ProviderEventType.stale);
    await delivered;
  }

  @override
  Future<void> shutdown() => _events.close();
}
