import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';

Future<void> main() async {
  final api = OpenFeatureAPI();
  await api.setProviderAndWait(InMemoryProvider({'checkout-enabled': true}));
  final client = api.getClient('checkout');
  try {
    final audit = EvaluationHook(
      metadata: const HookMetadata(name: 'audit'),
      before: (context, hints) {
        context.hookData.set('started', DateTime.now());
        return EvaluationContext.immutable(attributes: {'source': 'server'});
      },
      after: (context, details, hints) {
        print('${context.flagKey}: ${details.value} (${details.reason})');
      },
      error: (context, error, hints) {
        print('Evaluation failed: $error');
      },
      finallyAfter: (context, details, hints) {
        print(
          'Request ${hints.hints['requestId']} completed: ${details.value}',
        );
        final started = context.hookData.get('started') as DateTime?;
        if (started != null) print(DateTime.now().difference(started));
      },
    );
    final result = await client.getBooleanValue(
      'checkout-enabled',
      defaultValue: false,
      context: EvaluationContext.immutable(targetingKey: 'user-123'),
      options: EvaluationOptions(
        hooks: [audit],
        hints: HookHints.immutable({'requestId': 'request-456'}),
      ),
    );
    print('Application value: $result');
  } finally {
    await client.dispose();
    await OpenFeatureAPI.resetInstance();
  }
}
