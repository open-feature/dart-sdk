import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';

class ErrorValueProvider extends InMemoryProvider {
  ErrorValueProvider() : super({}) {
    setState(ProviderState.READY);
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async => FlagEvaluationResult(
    flagKey: flagKey,
    value: !defaultValue,
    reason: 'STATIC',
    errorCode: ErrorCode.GENERAL,
    errorMessage: 'remote failure',
    evaluatedAt: DateTime.now(),
  );
}

FeatureClient clientFor(FeatureProvider provider) => FeatureClient(
  metadata: ClientMetadata(name: 'consumer'),
  hookManager: HookManager(),
  defaultContext: const EvaluationContext(attributes: {}),
  provider: provider,
);

void main() {
  test('1.4.10 provider error must use the application default', () async {
    final client = clientFor(ErrorValueProvider());
    addTearDown(client.dispose);
    final result = await client.getBooleanDetails('flag', defaultValue: true);
    expect(result.value, isTrue);
    expect(result.reason, 'ERROR');
    expect(result.errorCode, ErrorCode.GENERAL);
  });

  test('1.2.2 client metadata does not retain mutable caller attributes', () {
    final attributes = {'component': 'matching'};
    final metadata = ClientMetadata(name: 'riders', attributes: attributes);
    attributes['component'] = 'changed';
    expect(metadata.attributes['component'], 'matching');
    expect(
      () => metadata.attributes['component'] = 'changed',
      throwsUnsupportedError,
    );
  });
}
