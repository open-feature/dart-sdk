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

  test('non-awaiting mutators preserve ordered static context', () async {
    final defaultProvider = _ImmediateLifecycleProvider(name: 'default');
    final domainProvider = _ImmediateLifecycleProvider(name: 'domain');
    final defaultReady = Completer<void>();
    final domainReady = Completer<void>();
    api.getClient().addHandler(ProviderEventType.ready, (details) {
      if (details.providerMetadata.name == 'default' &&
          !defaultReady.isCompleted) {
        defaultReady.complete();
      }
    });
    api.getClient('checkout').addHandler(ProviderEventType.ready, (details) {
      if (details.providerMetadata.name == 'domain' &&
          !domainReady.isCompleted) {
        domainReady.complete();
      }
    });

    api.setProvider(defaultProvider);
    await defaultReady.future;
    api.setProviderForDomain('checkout', domainProvider);
    await domainReady.future;
    expect(api.getProviderMetadata().name, 'default');
    expect(api.getProviderMetadata('checkout').name, 'domain');

    final global = EvaluationContext(targetingKey: 'global');
    api.setEvaluationContext(global);
    await Future.wait([
      defaultProvider.waitForChanges(1),
      domainProvider.waitForChanges(1),
    ]);

    final domain = EvaluationContext(targetingKey: 'domain');
    api.setEvaluationContextForDomain('checkout', domain);
    await domainProvider.waitForChanges(2);
    expect(domainProvider.changes.last, (global, domain));

    api.clearEvaluationContextForDomain('checkout');
    await domainProvider.waitForChanges(3);
    expect(domainProvider.changes.last, (domain, global));

    api.setEvaluationContextForDomain('unbound', domain);
    await Future<void>.delayed(Duration.zero);
    api.clearEvaluationContextForDomain('unbound');
    await Future<void>.delayed(Duration.zero);

    await api.setProviderAndWait(defaultProvider);
    await api.setProviderForDomainAndWait('checkout', domainProvider);
    expect(defaultProvider.initializeCalls, 1);
    expect(domainProvider.initializeCalls, 1);
  });

  test('non-awaiting lifecycle failures remain contained', () async {
    final errors = <Object>[];

    await runZonedGuarded(() async {
      api.setProvider(_LifecycleProviderWithoutEvents());
      await api.setProviderAndWait(InMemoryProvider({'replacement': true}));
    }, (error, _) => errors.add(error));

    expect(errors, isEmpty);
    expect(api.getClient().providerStatus, ProviderStatus.ready);
    expect(api.getClient().getBooleanValue('replacement', false), isTrue);
  });

  test('no-op provider supports every typed evaluation method', () {
    final client = api.getClient();

    expect(client.getBooleanValue('flag', true), isTrue);
    expect(client.getStringValue('flag', 'default'), 'default');
    expect(client.getIntegerValue('flag', 1), 1);
    expect(client.getDoubleValue('flag', 1.5), 1.5);
    expect(client.getStructureValue('flag', const {'safe': true}), {
      'safe': true,
    });
  });

  test('default hook stages and hook failures remain contained', () async {
    await api.setProviderAndWait(InMemoryProvider({'flag': true}));
    api.addHooks([const _EmptyHook(), _ThrowingFinalHook()]);
    final client = api.getClient();

    expect(client.getBooleanValue('flag', false), isTrue);
    expect(client.getBooleanValue('missing', false), isFalse);
  });

  test(
    'provider metadata and OpenFeature exceptions return defaults',
    () async {
      await api.setProviderAndWait(_LateMetadataFailureProvider());
      var details = api.getClient().getBooleanDetails('flag', false);

      expect(details.value, isFalse);
      expect(details.errorCode, ErrorCode.general);

      await api.setProviderAndWait(_OpenFeatureThrowingProvider());
      details = api.getClient().getBooleanDetails('flag', false);
      expect(details.value, isFalse);
      expect(details.errorCode, ErrorCode.providerFatal);
      expect(
        const OpenFeatureException(
          'fatal',
          errorCode: ErrorCode.providerFatal,
        ).toString(),
        'OpenFeatureException: fatal (providerFatal)',
      );
    },
  );

  test('reconciliation errors preserve the previous active context', () async {
    final provider = _ReconciliationErrorProvider();
    await api.setProviderAndWait(provider);

    await expectLater(
      api.setEvaluationContextAndWait(
        EvaluationContext(targetingKey: 'rejected'),
      ),
      throwsA(
        isA<OpenFeatureException>().having(
          (error) => error.errorCode,
          'errorCode',
          ErrorCode.general,
        ),
      ),
    );

    expect(api.getClient().providerStatus, ProviderStatus.error);
    api.getClient().getBooleanValue('flag', false);
    expect(provider.lastEvaluationContext, same(EvaluationContext.empty));
    await api.setProviderAndWait(InMemoryProvider({'flag': true}));
    expect(api.getClient().getBooleanValue('flag', false), isTrue);
  });

  test('invalid nested values and flags report their exact boundary', () {
    expect(
      () => EvaluationContext(
        attributes: {
          'invalid': <Object?, Object?>{1: true},
        },
      ),
      throwsArgumentError,
    );
    expect(() => InMemoryProvider({'flag': Object()}), throwsArgumentError);
  });
}

final class _EmptyHook extends HookAdapter {
  const _EmptyHook();
}

final class _ThrowingFinalHook extends HookAdapter {
  @override
  void finallyAfter(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {
    throw StateError('finally failed');
  }
}

class _DelegatingProvider implements FeatureProvider {
  _DelegatingProvider([Map<String, Object> flags = const {'flag': true}])
    : delegate = InMemoryProvider(flags);

  final InMemoryProvider delegate;

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'test-provider');

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => delegate.resolveBooleanValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => delegate.resolveDoubleValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => delegate.resolveIntegerValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => delegate.resolveStringValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => delegate.resolveStructureValue(flagKey, defaultValue, context);
}

final class _LifecycleProviderWithoutEvents extends _DelegatingProvider
    implements InitializableProvider {
  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {}
}

final class _ImmediateLifecycleProvider extends _DelegatingProvider
    implements
        InitializableProvider,
        ContextReconciliationProvider,
        ProviderEventSource {
  _ImmediateLifecycleProvider({required this.name});

  final String name;
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);
  final StreamController<int> _changeCounts = StreamController<int>.broadcast(
    sync: true,
  );
  final List<(EvaluationContext, EvaluationContext)> changes = [];
  int initializeCalls = 0;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  ProviderMetadata get metadata => ProviderMetadata(name: name);

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    initializeCalls++;
    _events.add(ProviderEvent(type: ProviderEventType.ready));
  }

  Future<void> waitForChanges(int count) async {
    if (changes.length >= count) {
      return;
    }
    await _changeCounts.stream.firstWhere((value) => value >= count);
  }

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    changes.add((previousContext, newContext));
    _events.add(ProviderEvent(type: ProviderEventType.contextChanged));
    _changeCounts.add(changes.length);
  }
}

final class _LateMetadataFailureProvider extends _DelegatingProvider {
  var metadataCalls = 0;

  @override
  ProviderMetadata get metadata {
    metadataCalls++;
    if (metadataCalls > 1) {
      throw StateError('metadata failed');
    }
    return super.metadata;
  }
}

final class _OpenFeatureThrowingProvider extends _DelegatingProvider {
  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) {
    throw const OpenFeatureException(
      'fatal',
      errorCode: ErrorCode.providerFatal,
    );
  }
}

final class _ReconciliationErrorProvider extends _DelegatingProvider
    implements ContextReconciliationProvider, ProviderEventSource {
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);
  EvaluationContext? lastEvaluationContext;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    _events.add(ProviderEvent(type: ProviderEventType.error));
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
