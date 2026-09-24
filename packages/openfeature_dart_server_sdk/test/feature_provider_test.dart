import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';

void main() {
  group('ProviderMetadata', () {
    test('creates with required name', () {
      final metadata = ProviderMetadata(name: 'TestProvider');
      expect(metadata.name, equals('TestProvider'));
      expect(metadata.version, equals('1.0.0'));
      expect(metadata.attributes, isEmpty);
    });

    test('creates with all parameters', () {
      final metadata = ProviderMetadata(
        name: 'TestProvider',
        version: '2.0.0',
        attributes: {'type': 'test'},
      );
      expect(metadata.name, equals('TestProvider'));
      expect(metadata.version, equals('2.0.0'));
      expect(metadata.attributes['type'], equals('test'));
    });
  });

  group('FlagEvaluationResult', () {
    test('creates successful result', () {
      final result = FlagEvaluationResult(
        flagKey: 'test-flag',
        value: true,
        reason: 'STATIC',
        evaluatedAt: DateTime.now(),
        evaluatorId: 'TestProvider',
      );

      expect(result.flagKey, equals('test-flag'));
      expect(result.value, isTrue);
      expect(result.reason, equals('STATIC'));
      expect(result.errorCode, isNull);
    });

    test('creates error result', () {
      final result = FlagEvaluationResult.error(
        'missing-flag',
        false,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag not found',
        evaluatorId: 'TestProvider',
      );

      expect(result.flagKey, equals('missing-flag'));
      expect(result.value, isFalse);
      expect(result.reason, equals('ERROR'));
      expect(result.errorCode, equals(ErrorCode.FLAG_NOT_FOUND));
      expect(result.errorMessage, equals('Flag not found'));
    });
  });

  group('ProviderConfig', () {
    test('creates with default values', () {
      final config = ProviderConfig();
      expect(config.connectionTimeout, equals(Duration(seconds: 30)));
      expect(config.maxRetries, equals(3));
      expect(config.enableCache, isTrue);
      expect(config.maxCacheSize, equals(1000));
    });

    test('creates with custom cache configuration', () {
      final config = ProviderConfig(
        enableCache: false,
        cacheTTL: Duration(minutes: 10),
        maxCacheSize: 500,
      );
      expect(config.enableCache, isFalse);
      expect(config.cacheTTL, equals(Duration(minutes: 10)));
      expect(config.maxCacheSize, equals(500));
    });
  });

  group('InMemoryProvider', () {
    late InMemoryProvider provider;
    final testFlags = {
      'bool-flag': true,
      'string-flag': 'test',
      'int-flag': 42,
      'double-flag': 3.14,
      'object-flag': {'key': 'value'},
    };

    setUp(() {
      provider = InMemoryProvider(testFlags);
    });

    test('has required metadata', () {
      expect(provider.metadata.name, equals('InMemoryProvider'));
      expect(provider.name, equals('InMemoryProvider'));
    });

    test('lifecycle state management', () async {
      expect(provider.state, equals(ProviderState.NOT_READY));

      await provider.initialize();
      expect(provider.state, equals(ProviderState.READY));

      await provider.shutdown();
      expect(provider.state, equals(ProviderState.SHUTDOWN));
    });

    test('throws when not ready', () async {
      expect(
        () => provider.getBooleanFlag('test', false),
        throwsA(isA<ProviderException>()),
      );
    });

    test('prevents initialization after shutdown', () async {
      await provider.shutdown();
      expect(() => provider.initialize(), throwsA(isA<ProviderException>()));
    });

    group('flag evaluation when ready', () {
      setUp(() async {
        await provider.initialize();
      });

      test('evaluates existing boolean flag', () async {
        final result = await provider.getBooleanFlag('bool-flag', false);
        expect(result.value, isTrue);
        expect(result.flagKey, equals('bool-flag'));
        expect(result.evaluatorId, equals('InMemoryProvider'));
        expect(result.reason, equals('STATIC'));
        expect(result.errorCode, isNull);
      });

      test('returns error for missing boolean flag', () async {
        final result = await provider.getBooleanFlag('missing-flag', true);
        expect(result.value, isTrue); // default value
        expect(result.errorCode, equals(ErrorCode.FLAG_NOT_FOUND));
        expect(result.reason, equals('ERROR'));
        expect(result.errorMessage, contains('not found'));
      });

      test('returns error for type mismatch', () async {
        final result = await provider.getBooleanFlag('string-flag', false);
        expect(result.value, isFalse); // default value
        expect(result.errorCode, equals(ErrorCode.TYPE_MISMATCH));
        expect(result.reason, equals('ERROR'));
        expect(result.errorMessage, contains('not a boolean'));
      });

      test('evaluates string flag', () async {
        final result = await provider.getStringFlag('string-flag', '');
        expect(result.value, equals('test'));
        expect(result.errorCode, isNull);
      });

      test('evaluates integer flag', () async {
        final result = await provider.getIntegerFlag('int-flag', 0);
        expect(result.value, equals(42));
        expect(result.errorCode, isNull);
      });

      test('evaluates double flag', () async {
        final result = await provider.getDoubleFlag('double-flag', 0.0);
        expect(result.value, equals(3.14));
        expect(result.errorCode, isNull);
      });

      test('evaluates object flag', () async {
        final result = await provider.getObjectFlag('object-flag', {});
        expect(result.value, equals({'key': 'value'}));
        expect(result.errorCode, isNull);
      });

      group('caching behavior', () {
        test('caches successful evaluations', () async {
          // First evaluation
          final result1 = await provider.getBooleanFlag('bool-flag', false);
          expect(result1.reason, equals('STATIC'));

          // Second evaluation should be cached
          final result2 = await provider.getBooleanFlag('bool-flag', false);
          expect(result2.reason, equals('CACHED'));
          expect(result2.value, equals(result1.value));
        });

        test('does not cache error results', () async {
          // First evaluation (error)
          final result1 = await provider.getBooleanFlag('missing-flag', false);
          expect(result1.errorCode, equals(ErrorCode.FLAG_NOT_FOUND));

          // Second evaluation should still be an error, not cached
          final result2 = await provider.getBooleanFlag('missing-flag', false);
          expect(result2.errorCode, equals(ErrorCode.FLAG_NOT_FOUND));
          expect(result2.reason, equals('ERROR'));
        });

        test('clears cache on shutdown', () async {
          // Cache a value
          await provider.getBooleanFlag('bool-flag', false);

          // Shutdown clears cache
          await provider.shutdown();

          // Reinitialize
          provider = InMemoryProvider(testFlags);
          await provider.initialize();

          // Should not be cached
          final result = await provider.getBooleanFlag('bool-flag', false);
          expect(result.reason, equals('STATIC'));
        });

        test('respects cache configuration', () async {
          final noCacheProvider = InMemoryProvider(
            testFlags,
            ProviderConfig(enableCache: false),
          );
          await noCacheProvider.initialize();

          // First evaluation
          final result1 = await noCacheProvider.getBooleanFlag(
            'bool-flag',
            false,
          );
          expect(result1.reason, equals('STATIC'));

          // Second evaluation should not be cached
          final result2 = await noCacheProvider.getBooleanFlag(
            'bool-flag',
            false,
          );
          expect(result2.reason, equals('STATIC'));
        });
      });
    });
  });

  group('ProviderException', () {
    test('creates with message and default code', () {
      final exception = ProviderException('Test error');
      expect(exception.message, equals('Test error'));
      expect(exception.code, equals(ErrorCode.GENERAL));
    });

    test('creates with specific error code', () {
      final exception = ProviderException(
        'Not ready',
        code: ErrorCode.PROVIDER_NOT_READY,
      );
      expect(exception.code, equals(ErrorCode.PROVIDER_NOT_READY));
      expect(exception.toString(), contains('PROVIDER_NOT_READY'));
    });
  });
}
