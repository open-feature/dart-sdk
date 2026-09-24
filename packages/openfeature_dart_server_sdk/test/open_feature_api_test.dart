import 'dart:async';

import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';

class TestProvider implements FeatureProvider {
  final Map<String, dynamic> _flags;
  final String _providerName;
  ProviderState _state;
  final bool _shouldFailInitialization;
  Map<String, dynamic>? lastEvaluationContext;
  int booleanEvaluationCount = 0;
  int shutdownCount = 0;

  TestProvider(
    this._flags, {
    String providerName = 'TestProvider',
    ProviderState state = ProviderState.NOT_READY,
    bool shouldFailInitialization = false,
  }) : _providerName = providerName,
       _state = state,
       _shouldFailInitialization = shouldFailInitialization;

  @override
  String get name => _providerName;

  @override
  ProviderState get state => _state;

  @override
  ProviderConfig get config => ProviderConfig();

  @override
  ProviderMetadata get metadata => ProviderMetadata(name: _providerName);

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    if (_shouldFailInitialization) {
      _state = ProviderState.ERROR;
      throw const ProviderException(
        'Initialization failed',
        code: ErrorCode.PROVIDER_NOT_READY,
      );
    }
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
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {}

  void setState(ProviderState newState) {
    _state = newState;
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    booleanEvaluationCount++;
    lastEvaluationContext = context == null ? null : {...context};
    if (_state != ProviderState.READY) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.PROVIDER_NOT_READY,
        'Provider not ready (state: $_state)',
        evaluatorId: name,
      );
    }

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! bool) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Type mismatch',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async => throw UnimplementedError();

  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async => throw UnimplementedError();

  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async => throw UnimplementedError();

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async => throw UnimplementedError();
}

class DelayedTestProvider extends TestProvider {
  final Completer<void> initializationStarted = Completer<void>();
  final Completer<void> allowInitialization = Completer<void>();
  final Completer<void> initializationCompleted = Completer<void>();

  DelayedTestProvider(
    Map<String, dynamic> flags, {
    required String providerName,
  }) : super(flags, providerName: providerName);

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    if (!initializationStarted.isCompleted) {
      initializationStarted.complete();
    }
    await allowInitialization.future;
    await super.initialize(config);
    if (!initializationCompleted.isCompleted) {
      initializationCompleted.complete();
    }
  }
}

class TestHook extends OpenFeatureHook {
  final List<String> calls = [];

  @override
  void beforeEvaluation(String flagKey, Map<String, dynamic>? context) {
    calls.add('before:$flagKey');
  }

  @override
  void afterEvaluation(String flagKey, result, Map<String, dynamic>? context) {
    calls.add('after:$flagKey:$result');
  }
}

void main() {
  group('OpenFeatureAPI', () {
    setUp(() async {
      await OpenFeatureAPI.resetInstance();
    });

    tearDown(() async {
      await OpenFeatureAPI.resetInstance();
    });

    test('singleton instance', () {
      final api1 = OpenFeatureAPI();
      final api2 = OpenFeatureAPI();
      expect(identical(api1, api2), isTrue);
    });

    test('reset awaits disposal before creating a replacement', () async {
      final original = OpenFeatureAPI();
      final eventsDone = original.events.drain<void>();

      await OpenFeatureAPI.resetInstance();
      await eventsDone;
      final replacement = OpenFeatureAPI();

      expect(identical(original, replacement), isFalse);
    });

    test('sets and gets provider', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});
      await api.setProvider(provider);
      expect(api.provider, equals(provider));
      expect(api.provider.state, equals(ProviderState.READY));
    });

    test('sets and gets global context', () {
      final api = OpenFeatureAPI();
      final context = OpenFeatureEvaluationContext({'key': 'value'});

      api.setGlobalContext(context);
      expect(api.globalContext?.attributes['key'], equals('value'));
    });

    test('merges evaluation contexts', () {
      final api = OpenFeatureAPI();
      final globalContext = OpenFeatureEvaluationContext({'global': 'value'});
      final localContext = OpenFeatureEvaluationContext({'local': 'value'});

      api.setGlobalContext(globalContext);

      final merged = globalContext.merge(localContext);
      expect(merged.attributes['global'], equals('value'));
      expect(merged.attributes['local'], equals('value'));
    });

    test(
      'existing clients use later global context and targeting-key changes',
      () async {
        final api = OpenFeatureAPI();
        final provider = TestProvider({'test-flag': true});
        await api.setProviderAndWait(provider);
        api.setGlobalContext(
          OpenFeatureEvaluationContext({
            'version': 'first',
          }, targetingKey: 'first-user'),
        );
        final client = api.getClient('test-client');

        await client.getBooleanFlag('test-flag');
        expect(provider.lastEvaluationContext?['version'], equals('first'));
        expect(
          provider.lastEvaluationContext?['targetingKey'],
          equals('first-user'),
        );

        api.setGlobalContext(
          OpenFeatureEvaluationContext({
            'version': 'second',
          }, targetingKey: 'second-user'),
        );
        await client.getBooleanFlag('test-flag');

        expect(provider.lastEvaluationContext?['version'], equals('second'));
        expect(
          provider.lastEvaluationContext?['targetingKey'],
          equals('second-user'),
        );
      },
    );

    test('evaluates boolean flag with hooks using new API', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test-flag': true});
      final hook = TestHook();
      await api.setProvider(provider);
      api.addHooks([hook]);

      final client = api.getClient('test-client');
      final result = await client.getBooleanFlag('test-flag');

      expect(result, isTrue);
      expect(hook.calls, contains('before:test-flag'));
      expect(hook.calls, contains('after:test-flag:true'));
    });

    test('handles provider not ready gracefully', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider(
        {'test-flag': true},
        state: ProviderState.NOT_READY,
        shouldFailInitialization: true,
      );

      await api.setProvider(provider);
      expect(api.provider.state, equals(ProviderState.ERROR));

      final client = api.getClient('test-client');
      final result = await client.getBooleanFlag('test-flag');

      expect(result, isFalse);
    });

    test('binds client to provider', () {
      final api = OpenFeatureAPI();
      api.bindClientToProvider('client1', 'provider1');
    });

    test('routes domain-bound clients to registered providers', () async {
      final api = OpenFeatureAPI();
      final defaultProvider = TestProvider({
        'test': true,
      }, providerName: 'default-provider');
      final secondaryProvider = TestProvider({
        'test': false,
      }, providerName: 'secondary-provider');

      await api.setProvider(defaultProvider);
      api.registerProvider(secondaryProvider);
      final configured = api.events.firstWhere(
        (event) =>
            event.type == OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED &&
            event.domain == 'checkout',
      );
      api.bindClientToProvider('checkout', secondaryProvider.metadata.name);
      await configured;

      final client = api.getClient('checkout', domain: 'checkout');
      expect(
        client.provider.metadata.name,
        equals(secondaryProvider.metadata.name),
      );
    });

    test('latest concurrent domain binding request wins', () async {
      final api = OpenFeatureAPI();
      final slowProvider = DelayedTestProvider({
        'test': true,
      }, providerName: 'slow-provider');
      final fastProvider = TestProvider({
        'test': false,
      }, providerName: 'fast-provider');
      api.registerProvider(slowProvider, providerId: 'slow');
      api.registerProvider(fastProvider, providerId: 'fast');

      final slowBinding = api.bindClientToProviderAndWait('checkout', 'slow');
      await slowProvider.initializationStarted.future;
      await api.bindClientToProviderAndWait('checkout', 'fast');

      slowProvider.allowInitialization.complete();
      await slowBinding;

      final client = api.getClient('checkout', domain: 'checkout');
      expect(identical(client.provider, fastProvider), isTrue);
      expect(await client.getBooleanFlag('test'), isFalse);
    });

    test(
      'activates a pending provider over an existing domain binding',
      () async {
        final api = OpenFeatureAPI();
        final originalProvider = TestProvider({
          'test': true,
        }, providerName: 'original-provider');
        final replacementProvider = TestProvider({
          'test': false,
        }, providerName: 'replacement-provider');
        api.registerProvider(originalProvider, providerId: 'original');
        await api.bindClientToProviderAndWait('checkout', 'original');

        api.bindClientToProvider('checkout', 'replacement');
        final replacementBound = api.events.firstWhere(
          (event) =>
              event.type ==
                  OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED &&
              event.domain == 'checkout' &&
              identical(event.provider, replacementProvider),
        );
        api.registerProvider(replacementProvider, providerId: 'replacement');
        await replacementBound;

        final client = api.getClient('checkout', domain: 'checkout');
        expect(identical(client.provider, replacementProvider), isTrue);
        expect(await client.getBooleanFlag('test'), isFalse);
      },
    );

    test(
      'latest registered provider instance wins during initialization',
      () async {
        final api = OpenFeatureAPI();
        final originalProvider = TestProvider({
          'test': true,
        }, providerName: 'original-provider');
        final slowProvider = DelayedTestProvider({
          'test': true,
        }, providerName: 'slow-provider');
        final replacementProvider = TestProvider({
          'test': false,
        }, providerName: 'replacement-provider');
        api.registerProvider(originalProvider, providerId: 'original');
        await api.bindClientToProviderAndWait('checkout', 'original');
        api.registerProvider(slowProvider, providerId: 'replacement');

        api.bindClientToProvider('checkout', 'replacement');
        await slowProvider.initializationStarted.future;
        final replacementBound = api.events.firstWhere(
          (event) =>
              event.type ==
                  OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED &&
              event.domain == 'checkout' &&
              identical(event.provider, replacementProvider),
        );
        api.registerProvider(replacementProvider, providerId: 'replacement');
        await replacementBound;

        slowProvider.allowInitialization.complete();
        await slowProvider.initializationCompleted.future;
        await Future<void>.delayed(Duration.zero);

        final client = api.getClient('checkout', domain: 'checkout');
        expect(identical(client.provider, replacementProvider), isTrue);
        expect(await client.getBooleanFlag('test'), isFalse);
        expect(slowProvider.shutdownCount, 1);
      },
    );

    test('emits events on provider change', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});
      final events = <OpenFeatureEvent>[];

      api.events.listen(events.add);
      await api.setProvider(provider);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events.length, greaterThan(0));
      expect(
        events.any((e) => e.type == OpenFeatureEventType.PROVIDER_READY),
        isTrue,
      );
    });

    test('emits error events for flag evaluation issues', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider(
        {},
        state: ProviderState.NOT_READY,
        shouldFailInitialization: true,
      );
      final events = <OpenFeatureEvent>[];

      api.events.listen(events.add);
      await api.setProvider(provider);
      await Future.delayed(Duration(milliseconds: 10));

      // Provider initialization failure emits PROVIDER_ERROR
      expect(
        events.any((e) => e.type == OpenFeatureEventType.PROVIDER_ERROR),
        isTrue,
      );
      expect(
        events.any(
          (e) =>
              e.type == OpenFeatureEventType.PROVIDER_ERROR &&
              e.errorCode == ErrorCode.PROVIDER_NOT_READY,
        ),
        isTrue,
      );
    });

    test('supports explicit API event handlers', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});
      final events = <OpenFeatureEvent>[];

      final sub = api.addHandler(events.add);
      await api.setProvider(provider);
      await Future.delayed(Duration(milliseconds: 10));

      expect(events, isNotEmpty);
      await api.removeHandler(sub);
    });

    test('handles evaluation errors gracefully', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'string-flag': 'not-boolean'});
      await api.setProvider(provider);

      final client = api.getClient('test-client');
      final result = await client.getBooleanFlag('string-flag');
      expect(result, isFalse);
    });

    test('streams provider updates', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});
      final updates = <FeatureProvider>[];

      api.providerUpdates.listen(updates.add);
      await api.setProvider(provider);
      await Future.delayed(Duration(milliseconds: 10));

      expect(updates, contains(provider));
    });

    test('initializes default provider', () {
      final api = OpenFeatureAPI();

      expect(api.provider, isNotNull);
      expect(api.provider.name, equals('InMemoryProvider'));
      expect(api.provider.state, equals(ProviderState.READY));
    });

    test('provider metadata is accessible', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});

      await api.setProvider(provider);
      expect(api.provider.metadata.name, equals('TestProvider'));
    });

    test('getClient creates client with proper configuration', () async {
      final api = OpenFeatureAPI();
      final provider = TestProvider({'test': true});
      await api.setProvider(provider);

      final client = api.getClient('my-client');
      expect(client.metadata.name, equals('my-client'));
      expect(client.provider.name, equals('TestProvider'));
    });
  });
}
