import 'dart:io';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';

class FailureProvider extends InMemoryProvider {
  FailureProvider() : super({}) {
    setState(ProviderState.READY);
  }
  int calls = 0;
  FlagEvaluationResult<T> result<T>(String key, T other) {
    calls++;
    if (key == 'throw') throw StateError('provider failed');
    return FlagEvaluationResult(
      flagKey: key,
      value: other,
      reason: 'STATIC',
      errorCode: key == 'mismatch'
          ? ErrorCode.TYPE_MISMATCH
          : ErrorCode.GENERAL,
      errorMessage: 'remote failure',
      evaluatedAt: DateTime.now(),
    );
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async => result(key, false);

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String key,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async => result(key, 'provider');

  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String key,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async => result(key, 1);

  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String key,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async => result(key, 1.5);

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String key,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async => result(key, {'provider': true});
}

FeatureClient clientFor(
  FeatureProvider provider, {
  FeatureProvider Function()? resolver,
}) => FeatureClient(
  metadata: ClientMetadata(name: 'consumer'),
  hookManager: HookManager(),
  defaultContext: const EvaluationContext(attributes: {}),
  provider: provider,
  providerResolver: resolver ?? () => provider,
);
void main() {
  test(
    '1.2.2 requested domain survives default-provider replacement',
    () async {
      final api = OpenFeatureAPI();
      addTearDown(OpenFeatureAPI.resetInstance);
      final client = api.getClient('legacy-name', domain: 'matching');
      addTearDown(client.dispose);
      expect(client.metadata.domain, 'matching');
      expect(client.metadata.name, 'legacy-name');
      final provider = FailureProvider();
      await api.setProviderAndWait(provider);
      expect(client.provider, same(provider));
      expect(client.metadata.domain, 'matching');
      final domainProvider = FailureProvider();
      await api.setProviderForDomainAndWait(
        'matching',
        domainProvider,
        providerId: 'matching-provider',
      );
      expect(client.provider, same(domainProvider));
      expect(client.metadata.domain, 'matching');
    },
  );

  group('Boolean defaults: 1.3.1.1 / 1.4.1.1 / 1.4.10', () {
    for (final key in ['error', 'throw', 'mismatch']) {
      test('exact fallback on $key', () async {
        final client = clientFor(FailureProvider());
        addTearDown(client.dispose);
        final fallback = true;
        expect(
          await client.getBooleanValue(key, defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getBooleanEvaluationDetails(
          key,
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(details.reason, 'ERROR');
        expect(
          details.errorCode,
          key == 'mismatch' ? ErrorCode.TYPE_MISMATCH : ErrorCode.GENERAL,
        );
      });
    }
    for (final state in [ProviderState.NOT_READY, ProviderState.FATAL]) {
      test('1.7.6 short-circuits $state', () async {
        final provider = FailureProvider()..setState(state);
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final fallback = true;
        expect(
          await client.getBooleanValue('flag', defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getBooleanEvaluationDetails(
          'flag',
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(provider.calls, 0);
        expect(
          details.errorCode,
          state == ProviderState.FATAL
              ? ErrorCode.PROVIDER_FATAL
              : ErrorCode.PROVIDER_NOT_READY,
        );
      });
    }
    test('provider lookup failure cannot escape', () async {
      final client = clientFor(
        FailureProvider(),
        resolver: () => throw StateError('binding failed'),
      );
      addTearDown(client.dispose);
      final fallback = true;
      expect(
        await client.getBooleanValue('flag', defaultValue: fallback),
        same(fallback),
      );
      expect(
        (await client.getBooleanEvaluationDetails(
          'flag',
          defaultValue: fallback,
        )).errorCode,
        ErrorCode.GENERAL,
      );
    });
  });

  group('String defaults: 1.3.1.1 / 1.4.1.1 / 1.4.10', () {
    for (final key in ['error', 'throw', 'mismatch']) {
      test('exact fallback on $key', () async {
        final client = clientFor(FailureProvider());
        addTearDown(client.dispose);
        final fallback = 'application';
        expect(
          await client.getStringValue(key, defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getStringEvaluationDetails(
          key,
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(details.reason, 'ERROR');
        expect(
          details.errorCode,
          key == 'mismatch' ? ErrorCode.TYPE_MISMATCH : ErrorCode.GENERAL,
        );
      });
    }
    for (final state in [ProviderState.NOT_READY, ProviderState.FATAL]) {
      test('1.7.6 short-circuits $state', () async {
        final provider = FailureProvider()..setState(state);
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final fallback = 'application';
        expect(
          await client.getStringValue('flag', defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getStringEvaluationDetails(
          'flag',
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(provider.calls, 0);
        expect(
          details.errorCode,
          state == ProviderState.FATAL
              ? ErrorCode.PROVIDER_FATAL
              : ErrorCode.PROVIDER_NOT_READY,
        );
      });
    }
    test('provider lookup failure cannot escape', () async {
      final client = clientFor(
        FailureProvider(),
        resolver: () => throw StateError('binding failed'),
      );
      addTearDown(client.dispose);
      final fallback = 'application';
      expect(
        await client.getStringValue('flag', defaultValue: fallback),
        same(fallback),
      );
      expect(
        (await client.getStringEvaluationDetails(
          'flag',
          defaultValue: fallback,
        )).errorCode,
        ErrorCode.GENERAL,
      );
    });
  });

  group('Integer defaults: 1.3.1.1 / 1.4.1.1 / 1.4.10', () {
    for (final key in ['error', 'throw', 'mismatch']) {
      test('exact fallback on $key', () async {
        final client = clientFor(FailureProvider());
        addTearDown(client.dispose);
        final fallback = 42;
        expect(
          await client.getIntegerValue(key, defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getIntegerEvaluationDetails(
          key,
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(details.reason, 'ERROR');
        expect(
          details.errorCode,
          key == 'mismatch' ? ErrorCode.TYPE_MISMATCH : ErrorCode.GENERAL,
        );
      });
    }
    for (final state in [ProviderState.NOT_READY, ProviderState.FATAL]) {
      test('1.7.6 short-circuits $state', () async {
        final provider = FailureProvider()..setState(state);
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final fallback = 42;
        expect(
          await client.getIntegerValue('flag', defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getIntegerEvaluationDetails(
          'flag',
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(provider.calls, 0);
        expect(
          details.errorCode,
          state == ProviderState.FATAL
              ? ErrorCode.PROVIDER_FATAL
              : ErrorCode.PROVIDER_NOT_READY,
        );
      });
    }
    test('provider lookup failure cannot escape', () async {
      final client = clientFor(
        FailureProvider(),
        resolver: () => throw StateError('binding failed'),
      );
      addTearDown(client.dispose);
      final fallback = 42;
      expect(
        await client.getIntegerValue('flag', defaultValue: fallback),
        same(fallback),
      );
      expect(
        (await client.getIntegerEvaluationDetails(
          'flag',
          defaultValue: fallback,
        )).errorCode,
        ErrorCode.GENERAL,
      );
    });
  });

  group('Double defaults: 1.3.1.1 / 1.4.1.1 / 1.4.10', () {
    for (final key in ['error', 'throw', 'mismatch']) {
      test('exact fallback on $key', () async {
        final client = clientFor(FailureProvider());
        addTearDown(client.dispose);
        final fallback = 3.25;
        expect(
          await client.getDoubleValue(key, defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getDoubleEvaluationDetails(
          key,
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(details.reason, 'ERROR');
        expect(
          details.errorCode,
          key == 'mismatch' ? ErrorCode.TYPE_MISMATCH : ErrorCode.GENERAL,
        );
      });
    }
    for (final state in [ProviderState.NOT_READY, ProviderState.FATAL]) {
      test('1.7.6 short-circuits $state', () async {
        final provider = FailureProvider()..setState(state);
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final fallback = 3.25;
        expect(
          await client.getDoubleValue('flag', defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getDoubleEvaluationDetails(
          'flag',
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(provider.calls, 0);
        expect(
          details.errorCode,
          state == ProviderState.FATAL
              ? ErrorCode.PROVIDER_FATAL
              : ErrorCode.PROVIDER_NOT_READY,
        );
      });
    }
    test('provider lookup failure cannot escape', () async {
      final client = clientFor(
        FailureProvider(),
        resolver: () => throw StateError('binding failed'),
      );
      addTearDown(client.dispose);
      final fallback = 3.25;
      expect(
        await client.getDoubleValue('flag', defaultValue: fallback),
        same(fallback),
      );
      expect(
        (await client.getDoubleEvaluationDetails(
          'flag',
          defaultValue: fallback,
        )).errorCode,
        ErrorCode.GENERAL,
      );
    });
  });

  group('Object defaults: 1.3.1.1 / 1.4.1.1 / 1.4.10', () {
    for (final key in ['error', 'throw', 'mismatch']) {
      test('exact fallback on $key', () async {
        final client = clientFor(FailureProvider());
        addTearDown(client.dispose);
        final fallback = <String, dynamic>{'application': true};
        expect(
          await client.getObjectValue(key, defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getObjectEvaluationDetails(
          key,
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(details.reason, 'ERROR');
        expect(
          details.errorCode,
          key == 'mismatch' ? ErrorCode.TYPE_MISMATCH : ErrorCode.GENERAL,
        );
      });
    }
    for (final state in [ProviderState.NOT_READY, ProviderState.FATAL]) {
      test('1.7.6 short-circuits $state', () async {
        final provider = FailureProvider()..setState(state);
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final fallback = <String, dynamic>{'application': true};
        expect(
          await client.getObjectValue('flag', defaultValue: fallback),
          same(fallback),
        );
        final details = await client.getObjectEvaluationDetails(
          'flag',
          defaultValue: fallback,
        );
        expect(details.value, same(fallback));
        expect(provider.calls, 0);
        expect(
          details.errorCode,
          state == ProviderState.FATAL
              ? ErrorCode.PROVIDER_FATAL
              : ErrorCode.PROVIDER_NOT_READY,
        );
      });
    }
    test('provider lookup failure cannot escape', () async {
      final client = clientFor(
        FailureProvider(),
        resolver: () => throw StateError('binding failed'),
      );
      addTearDown(client.dispose);
      final fallback = <String, dynamic>{'application': true};
      expect(
        await client.getObjectValue('flag', defaultValue: fallback),
        same(fallback),
      );
      expect(
        (await client.getObjectEvaluationDetails(
          'flag',
          defaultValue: fallback,
        )).errorCode,
        ErrorCode.GENERAL,
      );
    });
  });

  test(
    '1.3.1.1 / 1.4.1.1 compile-time defaults and legacy compatibility',
    () async {
      final dir = await Directory('test').createTemp('required-defaults-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/consumer.dart');
      const header =
          "import 'package:openfeature_dart_server_sdk/client.dart';\nvoid check(FeatureClient c) {\n";
      const methods = ['Boolean', 'String', 'Integer', 'Double', 'Object'];
      final missing = methods
          .expand(
            (t) => [
              "c.get${t}Value('flag');",
              "c.get${t}EvaluationDetails('flag');",
            ],
          )
          .join('\n');
      await file.writeAsString(header + missing + '\n}');
      final rejected = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--format=machine',
        file.path,
      ]);
      final diagnostics = '${rejected.stdout}\n${rejected.stderr}';
      expect(rejected.exitCode, isNot(0));
      expect(
        RegExp('MISSING_REQUIRED_ARGUMENT').allMatches(diagnostics).length,
        10,
        reason: diagnostics,
      );
      final legacy = methods
          .expand(
            (t) => ["c.get${t}Flag('flag');", "c.get${t}Details('flag');"],
          )
          .join('\n');
      await file.writeAsString(header + legacy + '\n}');
      final accepted = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--format=machine',
        file.path,
      ]);
      expect(
        accepted.exitCode,
        0,
        reason: '${accepted.stdout}\n${accepted.stderr}',
      );
    },
    timeout: Timeout(Duration(minutes: 2)),
  );
}
