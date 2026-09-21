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

  group('API and client', () {
    test(
      'default singleton and isolated APIs keep independent state',
      () async {
        final isolatedA = createIsolatedOpenFeatureAPI();
        final isolatedB = createIsolatedOpenFeatureAPI();
        addTearDown(isolatedA.shutdown);
        addTearDown(isolatedB.shutdown);

        await isolatedA.setProviderAndWait(InMemoryProvider({'flag': true}));

        expect(OpenFeatureAPI.instance, same(OpenFeatureAPI.instance));
        expect(isolatedA, isNot(same(isolatedB)));
        expect(isolatedA.getClient().getBooleanValue('flag', false), isTrue);
        expect(isolatedB.getClient().getBooleanValue('flag', false), isFalse);
      },
    );

    test('no-op provider returns the application default', () {
      final client = api.getClient();

      final details = client.getBooleanDetails('missing', true);

      expect(details.value, isTrue);
      expect(details.flagKey, 'missing');
      expect(details.errorCode, ErrorCode.providerNotReady);
      expect(details.flagMetadata, isEmpty);
      expect(client.providerStatus, ProviderStatus.notReady);
    });

    test('client evaluation methods do not accept evaluation context', () {
      final client = api.getClient();

      final bool Function(String, bool, {EvaluationOptions? options}) evaluate =
          client.getBooleanValue;

      expect(evaluate('flag', false), isFalse);
    });

    test(
      'domain clients select a domain provider and global fallback',
      () async {
        await api.setProviderAndWait(InMemoryProvider({'flag': false}));
        await api.setProviderForDomainAndWait(
          'checkout',
          InMemoryProvider({'flag': true}),
        );

        expect(api.getClient().getBooleanValue('flag', true), isFalse);
        expect(
          api.getClient('checkout').getBooleanValue('flag', false),
          isTrue,
        );
        expect(api.getClient('unknown').getBooleanValue('flag', true), isFalse);
        expect(api.getClient('checkout').metadata.domain, 'checkout');
        expect(api.getClient('checkout').metadata.name, 'checkout');
      },
    );

    test('provider exceptions never escape flag evaluation', () async {
      await api.setProviderAndWait(_ThrowingProvider());

      final details = api.getClient().getStringDetails('flag', 'default');

      expect(details.value, 'default');
      expect(details.errorCode, ErrorCode.general);
      expect(details.reason, 'ERROR');
    });

    test('provider errors cannot replace the application default', () async {
      await api.setProviderAndWait(_InvalidErrorValueProvider());

      final details = api.getClient().getBooleanDetails('flag', false);

      expect(details.value, isFalse);
      expect(details.errorCode, ErrorCode.flagNotFound);
    });
  });

  group('evaluation types', () {
    test('evaluation context is deeply immutable', () {
      final source = <String, Object?>{
        'groups': <Object?>[
          <String, Object?>{'name': 'admin'},
        ],
      };

      final context = EvaluationContext(
        targetingKey: 'user-123',
        attributes: source,
      );
      (source['groups']! as List<Object?>).clear();

      expect(context.targetingKey, 'user-123');
      expect(context.getValue('groups'), hasLength(1));
      expect(context.asMap()['targetingKey'], 'user-123');
      expect(() => context.attributes['new'] = true, throwsUnsupportedError);
      expect(
        () => (context.getValue('groups')! as List<Object?>).clear(),
        throwsUnsupportedError,
      );
    });

    test('flag metadata validates values and is immutable', () {
      final details = FlagEvaluationDetails<bool>(
        flagKey: 'flag',
        value: true,
        flagMetadata: {'cached': true, 'age': 2},
      );

      expect(details.flagMetadata, {'cached': true, 'age': 2});
      expect(
        () => details.flagMetadata['new'] = 'value',
        throwsUnsupportedError,
      );
      expect(
        () => flagMetadata({'nested': <String, Object>{}}),
        throwsArgumentError,
      );
    });

    test('evaluation context rejects unsupported field values', () {
      expect(
        () => EvaluationContext(attributes: {'value': Object()}),
        throwsArgumentError,
      );
    });

    test('evaluation context rejects a duplicate targeting key field', () {
      expect(
        () => EvaluationContext(
          targetingKey: 'one',
          attributes: {'targetingKey': 'two'},
        ),
        throwsArgumentError,
      );
    });
  });

  group('in-memory provider', () {
    test(
      'resolves every Dart flag type and reports abnormal results',
      () async {
        await api.setProviderAndWait(
          InMemoryProvider({
            'boolean': true,
            'string': 'value',
            'integer': 42,
            'double': 4.2,
            'structure': <String, Object?>{
              'items': <Object?>['one', 'two'],
            },
          }),
        );
        final client = api.getClient();

        expect(client.getBooleanValue('boolean', false), isTrue);
        expect(client.getStringValue('string', ''), 'value');
        expect(client.getIntegerValue('integer', 0), 42);
        expect(client.getDoubleValue('double', 0), 4.2);
        expect(client.getStructureValue('structure', const {}), {
          'items': ['one', 'two'],
        });
        expect(
          client.getBooleanDetails('string', false).errorCode,
          ErrorCode.typeMismatch,
        );
        expect(
          client.getBooleanDetails('missing', false).errorCode,
          ErrorCode.flagNotFound,
        );
      },
    );

    test('replaceAll emits the union of old and new flag keys', () async {
      final provider = InMemoryProvider({'old': true, 'same': false});
      final event = provider.events.first;

      provider.replaceAll({'new': true, 'same': true});

      expect(
        await event,
        isA<ProviderEvent>()
            .having(
              (value) => value.type,
              'type',
              ProviderEventType.configurationChanged,
            )
            .having((value) => value.flagsChanged, 'flagsChanged', [
              'new',
              'old',
              'same',
            ]),
      );
    });
  });

  group('hooks', () {
    test(
      'runs API, client, invocation, and provider hooks as a stack',
      () async {
        final calls = <String>[];
        final provider = _HookProvider(
          {'flag': true},
          [_RecordingHook('provider', calls)],
        );
        await api.setProviderAndWait(provider);
        api.addHooks([_RecordingHook('api', calls)]);
        final client = api.getClient()
          ..addHooks([_RecordingHook('client', calls)]);

        final result = client.getBooleanValue(
          'flag',
          false,
          options: EvaluationOptions(
            hooks: [_RecordingHook('invocation', calls)],
            hookHints: {'source': 'test'},
          ),
        );

        expect(result, isTrue);
        expect(calls, [
          'api.before:test',
          'client.before:test',
          'invocation.before:test',
          'provider.before:test',
          'provider.after',
          'invocation.after',
          'client.after',
          'api.after',
          'provider.finally',
          'invocation.finally',
          'client.finally',
          'api.finally',
        ]);
      },
    );

    test('contains before-hook failures and returns the default', () async {
      final calls = <String>[];
      final provider = _HookProvider({'flag': true}, const []);
      await api.setProviderAndWait(provider);
      final client = api.getClient()
        ..addHooks([
          _RecordingHook('first', calls, throwBefore: true),
          _RecordingHook('skipped', calls),
        ]);

      final details = client.getBooleanDetails('flag', false);

      expect(details.value, isFalse);
      expect(details.errorCode, ErrorCode.general);
      expect(provider.booleanCalls, 0);
      expect(calls, [
        'first.before:null',
        'skipped.error',
        'first.error',
        'skipped.finally',
        'first.finally',
      ]);
    });

    test('structured defaults are immutable within hook context', () async {
      final provider = _HookProvider(const {}, const []);
      final mutationErrors = <Object>[];
      await api.setProviderAndWait(provider);
      final source = <String, Object?>{
        'nested': <String, Object?>{'enabled': false},
      };
      final client = api.getClient()
        ..addHooks([_DefaultMutationHook(mutationErrors)]);

      final value = client.getStructureValue('missing', source);

      expect(mutationErrors.single, isA<UnsupportedError>());
      expect(source, {
        'nested': {'enabled': false},
      });
      expect(value, source);
    });
  });

  group('tracking', () {
    test('uses static context and immutable tracking details', () async {
      final provider = _TrackingProvider();
      final context = EvaluationContext(targetingKey: 'user-123');
      final source = <String, Object?>{
        'cart': <String, Object?>{'items': 2},
      };
      final details = TrackingEventDetails(value: 42, attributes: source);
      await api.setEvaluationContextAndWait(context);
      await api.setProviderAndWait(provider);

      api.getClient().track('checkout', details: details);
      (source['cart']! as Map<String, Object?>)['items'] = 3;

      expect(provider.trackingEventName, 'checkout');
      expect(provider.trackingContext, same(context));
      expect(provider.trackingDetails?.attributes, {
        'cart': {'items': 2},
      });
    });

    test('contains provider tracking failures', () async {
      await api.setProviderAndWait(_TrackingProvider(throwOnTrack: true));

      expect(() => api.getClient().track('event'), returnsNormally);
    });
  });

  group('provider lifecycle contracts', () {
    test('waits for provider-owned ready event', () async {
      final provider = _LifecycleProvider();

      await api.setProviderAndWait(provider);

      expect(provider.initialContext, same(EvaluationContext.empty));
      expect(api.getClient().providerStatus, ProviderStatus.ready);
    });

    test('applies concurrent provider requests in call order', () async {
      final slow = _DelayedLifecycleProvider();

      final firstRequest = api.setProviderAndWait(slow);
      final latestRequest = api.setProviderAndWait(
        InMemoryProvider({'flag': true}),
      );
      slow.allowInitialization();
      await Future.wait([firstRequest, latestRequest]);

      expect(api.getClient().getBooleanValue('flag', false), isTrue);
    });

    test('waits for provider-owned context changed event', () async {
      final provider = _LifecycleProvider();
      await api.setProviderAndWait(provider);
      final context = EvaluationContext(targetingKey: 'user-123');

      await api.setEvaluationContextAndWait(context);

      expect(provider.newContext, same(context));
      expect(api.getClient().providerStatus, ProviderStatus.ready);
    });

    test('serializes rapid static-context changes', () async {
      final provider = _LifecycleProvider();
      await api.setProviderAndWait(provider);
      final first = EvaluationContext(targetingKey: 'first');
      final second = EvaluationContext(targetingKey: 'second');

      final firstChange = api.setEvaluationContextAndWait(first);
      final secondChange = api.setEvaluationContextAndWait(second);
      await Future.wait([firstChange, secondChange]);

      expect(provider.contextChanges, [
        (EvaluationContext.empty, first),
        (first, second),
      ]);
    });

    test('requires event support for lifecycle methods', () async {
      await expectLater(
        api.setProviderAndWait(_LifecycleProviderWithoutEvents()),
        throwsA(isA<OpenFeatureException>()),
      );
    });

    test('keeps an error provider bound after failed initialization', () async {
      final provider = _FailingLifecycleProvider();

      await expectLater(
        api.setProviderAndWait(provider),
        throwsA(isA<OpenFeatureException>()),
      );

      final client = api.getClient();
      expect(client.providerStatus, ProviderStatus.fatal);
      expect(
        client.getBooleanDetails('flag', false).errorCode,
        ErrorCode.providerFatal,
      );
    });

    test('rejects a second domain for a domain-scoped provider', () async {
      final provider = _DomainScopedInMemoryProvider({'flag': true});
      await api.setProviderForDomainAndWait('one', provider);

      await expectLater(
        api.setProviderForDomainAndWait('two', provider),
        throwsA(isA<OpenFeatureException>()),
      );

      expect(api.getClient('one').getBooleanValue('flag', false), isTrue);
      expect(api.getClient('two').getBooleanValue('flag', false), isFalse);
    });

    test('shuts a provider down after its final binding is removed', () async {
      final first = _ShutdownProvider({'flag': true});
      await api.setProviderAndWait(first);
      await api.setProviderForDomainAndWait('shared', first);

      await api.setProviderAndWait(InMemoryProvider());
      expect(first.shutdownCalls, 0);

      await api.setProviderForDomainAndWait('shared', InMemoryProvider());
      expect(first.shutdownCalls, 1);
    });

    test(
      'replacement shuts down a provider when event cleanup fails',
      () async {
        final provider = _CancelFailingShutdownProvider();
        await api.setProviderAndWait(provider);

        await expectLater(
          api.setProviderAndWait(InMemoryProvider({'flag': true})),
          throwsA(isA<StateError>()),
        );

        expect(provider.shutdownCalls, 1);
        expect(api.getClient().getBooleanValue('flag', false), isTrue);
      },
    );

    test(
      'API shutdown remains unconditional when event cleanup fails',
      () async {
        final failingCleanup = _CancelFailingShutdownProvider();
        final otherProvider = _ShutdownProvider(const {});
        await api.setProviderAndWait(failingCleanup);
        await api.setProviderForDomainAndWait('other', otherProvider);

        await expectLater(api.shutdown(), throwsA(isA<StateError>()));

        expect(failingCleanup.shutdownCalls, 1);
        expect(otherProvider.shutdownCalls, 1);
        expect(api.getClient().providerStatus, ProviderStatus.notReady);
      },
    );
  });
}

class _ThrowingProvider extends _TestProvider {
  _ThrowingProvider() : super(const {});

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) {
    throw StateError('provider failed');
  }
}

class _InvalidErrorValueProvider extends _TestProvider {
  _InvalidErrorValueProvider() : super(const {});

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) {
    return ResolutionDetails<bool>(
      value: true,
      errorCode: ErrorCode.flagNotFound,
      reason: 'ERROR',
    );
  }
}

class _LifecycleProvider extends _TestProvider
    implements
        InitializableProvider,
        ContextReconciliationProvider,
        ProviderEventSource {
  _LifecycleProvider() : super(const {});

  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);
  EvaluationContext? initialContext;
  EvaluationContext? newContext;
  final List<(EvaluationContext, EvaluationContext)> contextChanges = [];

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    initialContext = context;
    _events.add(ProviderEvent(type: ProviderEventType.ready));
  }

  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) async {
    this.newContext = newContext;
    contextChanges.add((previousContext, newContext));
    _events
      ..add(ProviderEvent(type: ProviderEventType.reconciling))
      ..add(ProviderEvent(type: ProviderEventType.contextChanged));
  }
}

class _LifecycleProviderWithoutEvents extends _TestProvider
    implements InitializableProvider {
  _LifecycleProviderWithoutEvents() : super(const {});

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {}
}

class _DelayedLifecycleProvider extends _TestProvider
    implements InitializableProvider, ProviderEventSource {
  _DelayedLifecycleProvider() : super(const {});

  final Completer<void> _initializationGate = Completer<void>();
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);

  @override
  Stream<ProviderEvent> get events => _events.stream;

  void allowInitialization() => _initializationGate.complete();

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    await _initializationGate.future;
    _events.add(ProviderEvent(type: ProviderEventType.ready));
  }
}

class _FailingLifecycleProvider extends _TestProvider
    implements InitializableProvider, ProviderEventSource {
  _FailingLifecycleProvider() : super(const {});

  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    _events.add(
      ProviderEvent(
        type: ProviderEventType.error,
        errorCode: ErrorCode.providerFatal,
      ),
    );
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) {
    return ResolutionDetails<bool>(
      value: defaultValue,
      errorCode: ErrorCode.providerFatal,
      reason: 'ERROR',
    );
  }
}

class _DomainScopedInMemoryProvider extends _TestProvider
    implements DomainScopedProvider {
  _DomainScopedInMemoryProvider(super.flags);
}

class _ShutdownProvider extends _TestProvider implements ShutdownProvider {
  _ShutdownProvider(super.flags);

  int shutdownCalls = 0;

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
  }
}

class _CancelFailingShutdownProvider extends _TestProvider
    implements ProviderEventSource, ShutdownProvider {
  _CancelFailingShutdownProvider() : super(const {});

  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>(
        onCancel: () =>
            Future<void>.error(StateError('event subscription cleanup failed')),
      );
  int shutdownCalls = 0;

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
  }
}

final class _DefaultMutationHook extends HookAdapter {
  const _DefaultMutationHook(this.errors);

  final List<Object> errors;

  @override
  void before(HookContext context, HookHints hints) {
    try {
      final defaultValue = context.defaultValue as Map<String, Object?>;
      final nested = defaultValue['nested']! as Map<String, Object?>;
      nested['enabled'] = true;
    } on Object catch (error) {
      errors.add(error);
    }
  }
}

class _HookProvider extends _TestProvider implements ProviderHooks {
  _HookProvider(super.flags, this.hooks);

  @override
  final List<Hook> hooks;

  int booleanCalls = 0;

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) {
    booleanCalls++;
    return super.resolveBooleanValue(flagKey, defaultValue, context);
  }
}

class _TrackingProvider extends _TestProvider implements TrackingProvider {
  _TrackingProvider({this.throwOnTrack = false}) : super(const {});

  final bool throwOnTrack;
  String? trackingEventName;
  EvaluationContext? trackingContext;
  TrackingEventDetails? trackingDetails;

  @override
  void track(
    String trackingEventName,
    EvaluationContext context, {
    TrackingEventDetails? details,
  }) {
    if (throwOnTrack) {
      throw StateError('tracking failed');
    }
    this.trackingEventName = trackingEventName;
    trackingContext = context;
    trackingDetails = details;
  }
}

final class _RecordingHook extends HookAdapter {
  _RecordingHook(this.name, this.calls, {this.throwBefore = false});

  final String name;
  final List<String> calls;
  final bool throwBefore;

  @override
  void before(HookContext context, HookHints hints) {
    calls.add('$name.before:${hints['source']}');
    context.hookData['name'] = name;
    if (throwBefore) {
      throw StateError('before failed');
    }
  }

  @override
  void after(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {
    if (context.hookData['name'] != name) {
      throw StateError('Hook data was not preserved.');
    }
    calls.add('$name.after');
  }

  @override
  void error(HookContext context, Object error, HookHints hints) {
    calls.add('$name.error');
  }

  @override
  void finallyAfter(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {
    calls.add('$name.finally');
  }
}

class _TestProvider implements FeatureProvider {
  _TestProvider(Map<String, Object> flags)
    : _provider = InMemoryProvider(flags);

  final InMemoryProvider _provider;

  @override
  ProviderMetadata get metadata => _provider.metadata;

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => _provider.resolveBooleanValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => _provider.resolveDoubleValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => _provider.resolveIntegerValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => _provider.resolveStringValue(flagKey, defaultValue, context);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => _provider.resolveStructureValue(flagKey, defaultValue, context);
}
