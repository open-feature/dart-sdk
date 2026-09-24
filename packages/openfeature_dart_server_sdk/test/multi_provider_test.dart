import 'package:test/test.dart';

import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/multi_provider.dart';

class _StubProvider implements FeatureProvider {
  _StubProvider({
    required this.providerName,
    this.booleanFlags = const {},
    this.shouldFailInitialization = false,
    this.shouldFailTracking = false,
  });

  final String providerName;
  final Map<String, bool> booleanFlags;
  final bool shouldFailInitialization;
  final bool shouldFailTracking;
  ProviderState _state = ProviderState.NOT_READY;
  int trackingCalls = 0;

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
    if (shouldFailInitialization) {
      _state = ProviderState.ERROR;
      throw ProviderException(
        'Initialization failed for $providerName',
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
    _state = ProviderState.SHUTDOWN;
  }

  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    if (shouldFailTracking) {
      throw ProviderException(
        'Tracking failed for $providerName',
        code: ErrorCode.GENERAL,
      );
    }
    trackingCalls++;
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    if (_state != ProviderState.READY) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.PROVIDER_NOT_READY,
        'Provider $providerName not ready.',
        evaluatorId: providerName,
      );
    }

    if (!booleanFlags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found in $providerName.',
        evaluatorId: providerName,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: booleanFlags[flagKey]!,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: providerName,
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

void main() {
  group('MultiProvider', () {
    test('returns the first successful result', () async {
      final primary = _StubProvider(
        providerName: 'PrimaryProvider',
        booleanFlags: {'feature-a': true},
      );
      final fallback = _StubProvider(
        providerName: 'FallbackProvider',
        booleanFlags: {'feature-a': false},
      );

      final multiProvider = MultiProvider([primary, fallback]);
      await multiProvider.initialize();

      final result = await multiProvider.getBooleanFlag('feature-a', false);

      expect(result.value, isTrue);
      expect(result.evaluatorId, equals('PrimaryProvider'));
    });

    test('falls back when a provider returns FLAG_NOT_FOUND', () async {
      final primary = _StubProvider(providerName: 'PrimaryProvider');
      final fallback = _StubProvider(
        providerName: 'FallbackProvider',
        booleanFlags: {'feature-a': true},
      );

      final multiProvider = MultiProvider([primary, fallback]);
      await multiProvider.initialize();

      final result = await multiProvider.getBooleanFlag('feature-a', false);

      expect(result.value, isTrue);
      expect(result.evaluatorId, equals('FallbackProvider'));
    });

    test(
      'returns the first non-FLAG_NOT_FOUND error if no provider succeeds',
      () async {
        final broken = _StubProvider(
          providerName: 'BrokenProvider',
          booleanFlags: const {},
        );
        final missing = _StubProvider(providerName: 'MissingProvider');

        final multiProvider = MultiProvider([broken, missing]);
        await broken.initialize();
        await missing.initialize();
        await broken.shutdown();

        final result = await multiProvider.getBooleanFlag('feature-a', false);

        expect(result.value, isFalse);
        expect(result.errorCode, equals(ErrorCode.PROVIDER_NOT_READY));
        expect(result.evaluatorId, equals('BrokenProvider'));
      },
    );

    test(
      'initialization succeeds when at least one provider becomes ready',
      () async {
        final broken = _StubProvider(
          providerName: 'BrokenProvider',
          shouldFailInitialization: true,
        );
        final healthy = _StubProvider(
          providerName: 'HealthyProvider',
          booleanFlags: {'feature-a': true},
        );

        final multiProvider = MultiProvider([broken, healthy]);
        await multiProvider.initialize();

        expect(multiProvider.state, equals(ProviderState.ERROR));
        final result = await multiProvider.getBooleanFlag('feature-a', false);
        expect(result.value, isTrue);
        expect(result.evaluatorId, equals('HealthyProvider'));
      },
    );

    test('fans out tracking calls to every provider', () async {
      final primary = _StubProvider(providerName: 'PrimaryProvider');
      final fallback = _StubProvider(providerName: 'FallbackProvider');

      final multiProvider = MultiProvider([primary, fallback]);
      await primary.initialize();
      await fallback.initialize();

      await multiProvider.track('checkout-completed');

      expect(primary.trackingCalls, equals(1));
      expect(fallback.trackingCalls, equals(1));
    });

    test('tracking is best-effort when one provider fails', () async {
      final primary = _StubProvider(
        providerName: 'PrimaryProvider',
        shouldFailTracking: true,
      );
      final fallback = _StubProvider(providerName: 'FallbackProvider');

      final multiProvider = MultiProvider([primary, fallback]);
      await primary.initialize();
      await fallback.initialize();

      await multiProvider.track('checkout-completed');

      expect(primary.trackingCalls, equals(0));
      expect(fallback.trackingCalls, equals(1));
    });
  });
}
