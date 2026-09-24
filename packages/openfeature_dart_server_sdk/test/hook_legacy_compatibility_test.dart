import 'dart:async';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';

class ObjectProvider extends InMemoryProvider {
  Map<String, dynamic> result = {'remote': true};
  bool fail = false;
  int calls = 0;
  Completer<void>? entered;
  Completer<void>? release;
  ObjectProvider() : super({});

  @override
  ProviderState get state => ProviderState.READY;

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    calls++;
    entered?.complete();
    await release?.future;
    if (fail) throw StateError('provider failure');
    return FlagEvaluationResult(
      flagKey: flagKey,
      value: result,
      evaluatedAt: DateTime.now(),
      evaluatorId: 'object-provider',
    );
  }
}

class LegacyObserver extends BaseHook {
  HookContext? observed;
  LegacyObserver() : super(metadata: const HookMetadata(name: 'legacy'));
  @override
  Future<void> after(HookContext context) async => observed = context;
}

void main() {
  late ObjectProvider provider;
  late FeatureClient client;
  setUp(() {
    provider = ObjectProvider();
    client = FeatureClient(
      metadata: ClientMetadata(name: 'compatibility'),
      hookManager: HookManager(),
      defaultContext: const EvaluationContext(attributes: {}),
      provider: provider,
    );
  });
  tearDown(() => client.dispose());

  test(
    'legacy object defaults cannot prevent a successful evaluation',
    () async {
      final fallback = {
        'opaque': Object(),
        'typed': <String>['fallback'],
      };
      final result = await client.getObjectDetails(
        'flag',
        defaultValue: fallback,
      );
      expect(result.value, same(provider.result));
      expect(result.errorCode, isNull);
      expect(provider.calls, 1);
    },
  );

  test(
    'legacy structured results retain opaque values and typed collections',
    () async {
      final opaque = Object();
      final typed = <String>['remote'];
      provider.result = {'opaque': opaque, 'typed': typed};
      final result = await client.getObjectDetails('flag');
      expect(result.value, same(provider.result));
      expect(result.value['opaque'], same(opaque));
      expect(result.value['typed'], same(typed));
      expect(result.errorCode, isNull);
    },
  );

  test('legacy provider failure returns the exact opaque fallback', () async {
    provider.fail = true;
    final fallback = {'opaque': Object()};
    final result = await client.getObjectDetails(
      'flag',
      defaultValue: fallback,
    );
    expect(result.value, same(fallback));
    expect(result.errorCode, ErrorCode.GENERAL);
    expect(provider.calls, 1);
  });

  test(
    'legacy hooks keep original default, result and nested context types',
    () async {
      final observer = LegacyObserver();
      client.addHook(observer);
      final nested = <String>['original'];
      final fallback = {'opaque': Object()};
      provider.result = {'remote': Object()};
      final result = await client.getObjectDetails(
        'flag',
        defaultValue: fallback,
        context: EvaluationContext(attributes: {'nested': nested}),
      );
      expect(result.errorCode, isNull);
      expect(observer.observed, isNotNull);
      expect(observer.observed!.defaultValue, same(fallback));
      expect(observer.observed!.result, same(provider.result));
      expect(
        observer.observed!.evaluationDetails!.value,
        same(provider.result),
      );
      expect(observer.observed!.evaluationContext['nested'], same(nested));
    },
  );

  test(
    'an after-only typed hook captures the default before the provider await',
    () async {
      provider.entered = Completer<void>();
      provider.release = Completer<void>();
      final fallback = <String, dynamic>{
        'nested': [1],
      };
      Map<String, dynamic>? observed;
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'after-only'),
          after: (context, details, hints) {
            observed = context.defaultValue as Map<String, dynamic>;
          },
        ),
      );
      final pending = client.getObjectDetails('flag', defaultValue: fallback);
      await provider.entered!.future.timeout(const Duration(seconds: 2));
      (fallback['nested'] as List).add(2);
      provider.release!.complete();
      await pending;
      expect(observed, {
        'nested': [1],
      });
      expect(
        () => (observed!['nested'] as List).add(3),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'invalid typed-hook context still runs error and finally observers',
    () async {
      final calls = <String>[];
      final opaque = Object();
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'typed'),
          before: (context, hints) {
            calls.add('before');
            return null;
          },
          error: (context, error, hints) {
            calls.add('error');
            expect(context.evaluationContext['opaque'], same(opaque));
          },
          finallyAfter: (context, details, hints) => calls.add('finally'),
        ),
      );
      final fallback = <String, dynamic>{'fallback': true};
      final result = await client.getObjectDetails(
        'flag',
        defaultValue: fallback,
        context: EvaluationContext(attributes: {'opaque': opaque}),
      );
      expect(result.value, same(fallback));
      expect(result.errorCode, ErrorCode.INVALID_CONTEXT);
      expect(provider.calls, 0);
      expect(calls, ['error', 'finally']);
    },
  );

  test(
    'invalid typed-hook fallback cannot throw or suppress cleanup',
    () async {
      final calls = <String>[];
      final fallback = <String, dynamic>{'opaque': Object()};
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'typed'),
          before: (context, hints) {
            calls.add('before');
            return null;
          },
          error: (context, error, hints) => calls.add('error'),
          finallyAfter: (context, details, hints) {
            calls.add('finally');
            expect(details.value, same(fallback));
          },
        ),
      );
      final result = await client.getObjectDetails(
        'flag',
        defaultValue: fallback,
      );
      expect(result.value, same(fallback));
      expect(result.errorCode, ErrorCode.GENERAL);
      expect(calls, ['error', 'finally']);
    },
  );

  test(
    'typed-hook result validation falls back and completes cleanup',
    () async {
      provider.result = {'opaque': Object()};
      final calls = <String>[];
      final fallback = <String, dynamic>{'fallback': true};
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'typed'),
          after: (context, details, hints) => calls.add('after'),
          error: (context, error, hints) => calls.add('error'),
          finallyAfter: (context, details, hints) {
            calls.add('finally');
            expect(details.value, fallback);
          },
        ),
      );
      final result = await client.getObjectDetails(
        'flag',
        defaultValue: fallback,
      );
      expect(result.value, same(fallback));
      expect(result.errorCode, ErrorCode.GENERAL);
      expect(calls, ['error', 'finally']);
    },
  );

  test('legacy cyclic result is not traversed by hook bookkeeping', () async {
    final cycle = <String, dynamic>{};
    cycle['self'] = cycle;
    provider.result = cycle;
    final result = await client.getObjectDetails('flag');
    expect(result.value, same(cycle));
    expect(result.errorCode, isNull);
  });
}
