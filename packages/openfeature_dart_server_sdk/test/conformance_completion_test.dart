import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:test/test.dart';

class AliasProvider extends InMemoryProvider {
  final fields = <String, dynamic>{
    'enabled': true,
    'cohort': 'test',
    'version': 2,
  };
  AliasProvider() : super({});
  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool value, {
    Map<String, dynamic>? context,
  }) async => FlagEvaluationResult(
    flagKey: 'internal-alias',
    value: true,
    reason: 'TARGETING_MATCH',
    variant: 'enabled',
    flagMetadata: fields,
    evaluatedAt: DateTime.now(),
  );
}

void main() {
  test('1.1.1 singleton identity is retained', () async {
    expect(OpenFeatureAPI(), same(OpenFeatureAPI()));
    await OpenFeatureAPI.resetInstance();
  });
  test('1.1.6 / 1.2.2 client domain is optional and immutable', () async {
    final api = createIsolatedOpenFeatureAPI();
    addTearDown(api.dispose);
    expect(api.createClient().metadata.domain, '');
    expect(api.createClient(domain: 'checkout').metadata.domain, 'checkout');
    expect(
      api.getClient('legacy', domain: 'explicit').metadata.domain,
      'explicit',
    );
  });
  test(
    '1.1.7 client creation after permanent disposal does not throw',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      await api.dispose();
      final client = api.createClient(domain: 'disposed');
      addTearDown(client.dispose);
      expect(client.providerStatus, ProviderState.NOT_READY);
      expect(await client.getBooleanValue('flag', defaultValue: true), isTrue);
      expect(api.getClient('legacy').metadata.domain, 'legacy');
    },
  );
  test(
    '1.4.3 / 1.4.5 / 1.4.6 / 1.4.7 SDK details retain invocation key and provider fields',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.dispose);
      await api.setProviderAndWait(AliasProvider());
      final result = await api.createClient().getBooleanEvaluationDetails(
        'public-key',
        defaultValue: false,
      );
      expect(result.flagKey, 'public-key');
      expect(result.value, isTrue);
      expect(result.variant, 'enabled');
      expect(result.reason, 'TARGETING_MATCH');
      expect(result.errorCode, isNull);
    },
  );
  test(
    '1.4.14 / 1.4.15.1 / 2.2.10 metadata preserves primitives and immutable details',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      addTearDown(api.dispose);
      final provider = AliasProvider();
      await api.setProviderAndWait(provider);
      final result = await api.createClient().getBooleanEvaluationDetails(
        'flag',
        defaultValue: false,
      );
      provider.fields['cohort'] = 'changed';
      expect(result.flagMetadata, {
        'enabled': true,
        'cohort': 'test',
        'version': 2,
      });
      expect(
        () => result.flagMetadata['cohort'] = 'mutated',
        throwsUnsupportedError,
      );
    },
  );
}
