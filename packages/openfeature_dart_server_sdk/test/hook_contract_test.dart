import 'dart:async';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/provider_capabilities.dart';

class HookProvider extends InMemoryProvider implements ProviderHooks {
  @override
  final List<Hook> hooks = [];
  final List<Map<String, dynamic>?> contexts = [];
  final attrs = <String, String>{'build': 'original'};
  bool fail = false;
  HookProvider()
    : super({
        'flag': true,
        'string': 'remote',
        'int': 42,
        'double': 1.5,
        'object': {'remote': true},
      });
  @override
  ProviderMetadata get metadata =>
      ProviderMetadata(name: 'hook-provider', attributes: attrs);
  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool fallback, {
    Map<String, dynamic>? context,
  }) async {
    contexts.add(context);
    if (fail)
      return FlagEvaluationResult.error(
        key,
        true,
        ErrorCode.PARSE_ERROR,
        'invalid configuration',
      );
    return super.getBooleanFlag(key, fallback, context: context);
  }
}

class EqualHook extends BaseHook {
  final List<HookData> data = [];
  final token = Object();
  EqualHook() : super(metadata: const HookMetadata(name: 'equal'));
  @override
  bool operator ==(Object other) => other is EqualHook;
  @override
  int get hashCode => 1;
  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    expect(context.hookData.containsKey('token'), false);
    context.hookData.set('token', token);
    data.add(context.hookData);
    return null;
  }

  @override
  Future<void> after(HookContext context) async {
    expect(context.hookData.get('token'), same(token));
  }
}

class UnformattableError implements Exception {
  @override
  String toString() => throw StateError('cannot format');
}

class BrokenMetadataHook implements Hook {
  @override
  HookMetadata get metadata => throw StateError('metadata failed');
  @override
  Future<Map<String, dynamic>?> before(HookContext context) async => null;
  @override
  Future<void> after(HookContext context) async {}
  @override
  Future<void> error(HookContext context) async {}
  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? details, [
    HookHints? hints,
  ]) async {}
}

void main() {
  late OpenFeatureAPI api;
  late HookProvider provider;
  late FeatureClient client;
  setUp(() async {
    api = OpenFeatureAPI();
    provider = HookProvider();
    await api.setProviderAndWait(provider);
    client = api.getClient('hooks', domain: 'requested');
  });
  tearDown(() async {
    await client.dispose();
    await OpenFeatureAPI.resetInstance();
  });

  EvaluationHook trace(String label, List<String> calls, {String? failure}) =>
      EvaluationHook(
        metadata: HookMetadata(name: label, priority: HookPriority.LOW),
        before: (context, hints) {
          calls.add('$label:before');
          if (failure == 'before') throw StateError(label);
          return null;
        },
        after: (context, details, hints) {
          calls.add('$label:after');
          if (failure == 'after') throw StateError(label);
        },
        error: (context, error, hints) {
          calls.add('$label:error');
          if (failure == 'error') throw StateError(label);
        },
        finallyAfter: (context, details, hints) {
          calls.add('$label:finally');
          if (failure == 'finally') throw StateError(label);
        },
      );

  test(
    '4.4.1-2 four scopes and within-scope insertion/reverse order',
    () async {
      final calls = <String>[];
      api.addEvaluationHooks([trace('A', calls), trace('B', calls)]);
      client.addHooks([trace('C', calls), trace('D', calls)]);
      provider.hooks.addAll([trace('G', calls), trace('H', calls)]);
      final options = EvaluationOptions(
        hooks: [trace('E', calls), trace('F', calls)],
      );
      expect(
        await client.getBooleanValue(
          'flag',
          defaultValue: false,
          options: options,
        ),
        true,
      );
      expect(calls, [
        for (final x in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) '$x:before',
        for (final x in ['H', 'G', 'F', 'E', 'D', 'C', 'B', 'A']) '$x:after',
        for (final x in ['H', 'G', 'F', 'E', 'D', 'C', 'B', 'A']) '$x:finally',
      ]);
    },
  );

  for (final failure in ['before', 'after', 'provider']) {
    test(
      '4.3.7-8 / 4.4.3-7 $failure failure short-circuits and completes cleanup',
      () async {
        final calls = <String>[];
        api.addEvaluationHooks([trace('A', calls)]);
        client.addHooks([
          trace('B', calls, failure: failure),
          trace('C', calls),
        ]);
        provider.hooks.add(trace('P', calls, failure: 'error'));
        provider.fail = failure == 'provider';
        EvaluationDetails? observed;
        final options = EvaluationOptions(
          hooks: [
            trace('I', calls, failure: 'finally'),
            EvaluationHook(
              metadata: const HookMetadata(name: 'observer'),
              finallyAfter: (context, details, hints) {
                observed = details;
              },
            ),
          ],
        );
        final result = await client.getBooleanEvaluationDetails(
          'flag',
          defaultValue: false,
          options: options,
        );
        expect(result.value, false);
        expect(observed!.value, result.value);
        expect(observed!.reason, result.reason);
        expect(observed!.errorCode, result.errorCode);
        expect(observed!.errorMessage, result.errorMessage);
        expect(observed!.flagMetadata, result.flagMetadata);
        expect(observed!.evaluationTime, result.timestamp);
        expect(calls.where((x) => x.endsWith(':error')), [
          'P:error',
          'I:error',
          'C:error',
          'B:error',
          'A:error',
        ]);
        expect(calls.where((x) => x.endsWith(':finally')), [
          'P:finally',
          'I:finally',
          'C:finally',
          'B:finally',
          'A:finally',
        ]);
        if (failure == 'before') {
          expect(calls.where((x) => x.endsWith(':before')), [
            'A:before',
            'B:before',
          ]);
          expect(provider.contexts, isEmpty);
        }
        if (failure == 'after')
          expect(calls.where((x) => x.endsWith(':after')), [
            'P:after',
            'I:after',
            'C:after',
            'B:after',
          ]);
        if (failure == 'provider')
          expect(calls.where((x) => x.endsWith(':after')), isEmpty);
      },
    );
  }

  test(
    '4.3.1 requires a stage; 4.3.2 creates data at first supported stage',
    () async {
      expect(
        () => EvaluationHook(metadata: const HookMetadata(name: 'empty')),
        throwsArgumentError,
      );
      HookData? data;
      final hook = EvaluationHook(
        metadata: const HookMetadata(name: 'after-only'),
        after: (context, details, hints) {
          data = context.hookData;
          context.hookData.set('arbitrary', provider);
        },
        finallyAfter: (context, details, hints) {
          expect(context.hookData, same(data));
          expect(context.hookData.get('arbitrary'), same(provider));
        },
      );
      expect(hook.stages, {HookStage.AFTER, HookStage.FINALLY});
      expect(() => hook.stages.add(HookStage.BEFORE), throwsUnsupportedError);
      await client.getBooleanValue(
        'flag',
        defaultValue: false,
        options: EvaluationOptions(hooks: [hook]),
      );
    },
  );

  test(
    '4.1.5 / 4.3.2 / 4.6.1 data uses hook identity and evaluation lifetime',
    () async {
      final first = EqualHook(), second = EqualHook();
      client.addHooks([first, second]);
      await Future.wait([
        client.getBooleanValue('flag', defaultValue: false),
        client.getBooleanValue('flag', defaultValue: false),
      ]);
      expect(first.data.length, 2);
      expect(second.data.length, 2);
      expect(identical(first.data[0], second.data[0]), false);
      expect(identical(first.data[0], first.data[1]), false);
      client.removeHook(first);
      await client.getBooleanValue('flag', defaultValue: false);
      expect(first.data.length, 2);
      expect(second.data.length, 3);
    },
  );

  test(
    '4.1.1-4 / 4.2.2 snapshots defaults, context, metadata across await',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final defaults = <String, dynamic>{
        'nested': [1],
      };
      final attrs = <String, dynamic>{
        'nested': [2],
      };
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'immutable'),
          before: (context, hints) async {
            expect(context.flagKey, 'object');
            expect(context.flagValueType, FlagValueType.OBJECT);
            expect(context.clientMetadata!.domain, 'requested');
            expect(
              () => context.clientMetadata!.attributes['bad'] = 'bad',
              throwsUnsupportedError,
            );
            expect(
              () => context.providerMetadata!.attributes['build'] = 'bad',
              throwsUnsupportedError,
            );
            expect(
              () => (context.defaultValue['nested'] as List).add(3),
              throwsUnsupportedError,
            );
            expect(
              () => (context.evaluationContext['nested'] as List).add(3),
              throwsUnsupportedError,
            );
            entered.complete();
            await release.future;
            expect(context.defaultValue, {
              'nested': [1],
            });
            expect(context.evaluationContext['nested'], [2]);
            return null;
          },
          after: (context, details, hints) {
            expect(context.defaultValue, {
              'nested': [1],
            });
            expect(context.providerMetadata!.attributes['build'], 'original');
            expect(
              () => (details.value as Map)['remote'] = false,
              throwsUnsupportedError,
            );
            expect(
              () => (context.result as Map)['remote'] = false,
              throwsUnsupportedError,
            );
          },
        ),
      );
      final pending = client.getObjectValue(
        'object',
        defaultValue: defaults,
        context: EvaluationContext(attributes: attrs),
      );
      await entered.future;
      (defaults['nested'] as List).add(9);
      (attrs['nested'] as List).add(9);
      provider.attrs['build'] = 'changed';
      release.complete();
      expect(await pending, {'remote': true});
    },
  );

  test(
    '4.2.1 / 4.5.1-3 hints are deeply captured and available to every stage',
    () async {
      final input = <String, dynamic>{
        'targetingKey': 123,
        'nested': [
          true,
          {'date': DateTime.utc(2026)},
        ],
      };
      final seen = <HookHints>[];
      void verify(HookHints hints) {
        seen.add(hints);
        expect(hints.hints['targetingKey'], 123);
        expect((hints.hints['nested'] as List).length, 2);
        expect(
          () => (hints.hints['nested'] as List).add(false),
          throwsUnsupportedError,
        );
        expect(
          () => ((hints.hints['nested'] as List)[1] as Map)['date'] = null,
          throwsUnsupportedError,
        );
      }

      final hook = EvaluationHook(
        metadata: const HookMetadata(name: 'hints'),
        before: (context, hints) {
          verify(hints);
          return null;
        },
        after: (context, details, hints) => verify(hints),
        error: (context, error, hints) => verify(hints),
        finallyAfter: (context, details, hints) => verify(hints),
      );
      final hooks = <Hook>[hook];
      final options = EvaluationOptions(
        hooks: hooks,
        hints: HookHints(hints: input),
      );
      hooks.clear();
      (input['nested'] as List).add(false);
      expect(() => options.hooks.clear(), throwsUnsupportedError);
      await client.getBooleanValue(
        'flag',
        defaultValue: false,
        options: options,
      );
      provider.fail = true;
      await client.getBooleanValue(
        'flag',
        defaultValue: false,
        options: options,
      );
      expect(seen.length, 6);
    },
  );

  for (final bad in [
    null,
    Object(),
    <int>{1},
    <int, String>{1: 'bad'},
  ]) {
    test('4.2.1 rejects unsupported hint type ${bad.runtimeType}', () {
      expect(() => HookHints.immutable({'bad': bad}), throwsArgumentError);
    });
  }
  test('4.2.1 rejects cyclic hints', () {
    final loop = <dynamic>[];
    loop.add(loop);
    expect(() => HookHints.immutable({'loop': loop}), throwsArgumentError);
  });

  test(
    '4.3.4-5 before contributions merge without mutating original context',
    () async {
      final attrs = <String, dynamic>{'keep': true, 'winner': 'invocation'};
      final contribution = <String, dynamic>{
        'nested': [1],
        'winner': 'first',
      };
      client.addHooks([
        EvaluationHook(
          metadata: const HookMetadata(name: 'first'),
          before: (context, hints) => EvaluationContext(
            attributes: contribution,
            targetingKey: 'hook-user',
          ),
        ),
        EvaluationHook(
          metadata: const HookMetadata(name: 'second'),
          before: (context, hints) {
            (contribution['nested'] as List).add(2);
            expect(context.evaluationContext['nested'], [1]);
            expect(context.evaluationContext['keep'], true);
            expect(context.evaluationContext['targetingKey'], 'hook-user');
            return EvaluationContext.immutable(
              attributes: {'winner': 'second'},
            );
          },
        ),
      ]);
      await client.getBooleanValue(
        'flag',
        defaultValue: false,
        context: EvaluationContext(attributes: attrs),
      );
      expect(provider.contexts.single, {
        'keep': true,
        'winner': 'second',
        'nested': [1],
        'targetingKey': 'hook-user',
      });
      expect(attrs, {'keep': true, 'winner': 'invocation'});
    },
  );

  test(
    '4.3.7 error/finally retain contributions made before a later failure',
    () async {
      final seen = <Map<String, dynamic>>[];
      client.addHooks([
        EvaluationHook(
          metadata: const HookMetadata(name: 'contribution'),
          before: (context, hints) =>
              EvaluationContext.immutable(attributes: {'added': true}),
        ),
        EvaluationHook(
          metadata: const HookMetadata(name: 'failure'),
          before: (context, hints) => throw StateError('fail'),
          error: (context, error, hints) => seen.add(context.evaluationContext),
          finallyAfter: (context, details, hints) =>
              seen.add(context.evaluationContext),
        ),
      ]);
      expect(await client.getBooleanValue('flag', defaultValue: false), false);
      expect(seen, [
        {'added': true},
        {'added': true},
      ]);
    },
  );

  test(
    '4.4.2 in-flight registration is stable; next invocation sees additions',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final calls = <String>[];
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'gate'),
          before: (context, hints) async {
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
            return null;
          },
        ),
      );
      final pending = client.getBooleanValue('flag', defaultValue: false);
      await entered.future;
      api.addEvaluationHooks([trace('new-api', calls)]);
      client.addHook(trace('new-client', calls));
      provider.hooks.add(trace('new-provider', calls));
      release.complete();
      await pending;
      expect(calls, isEmpty);
      await client.getBooleanValue('flag', defaultValue: false);
      expect(calls, [
        'new-api:before',
        'new-client:before',
        'new-provider:before',
        'new-provider:after',
        'new-client:after',
        'new-api:after',
        'new-provider:finally',
        'new-client:finally',
        'new-api:finally',
      ]);
    },
  );

  test(
    '4.4.7 object fallback retains application identity after hook failure',
    () async {
      final fallback = <String, dynamic>{
        'nested': [1],
      };
      EvaluationDetails? observed;
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'fail'),
          before: (context, hints) => throw StateError('failed'),
          finallyAfter: (context, details, hints) {
            observed = details;
          },
        ),
      );
      final result = await client.getObjectEvaluationDetails(
        'object',
        defaultValue: fallback,
      );
      expect(result.value, same(fallback));
      expect(observed!.value, fallback);
      expect(
        () => (observed!.value['nested'] as List).add(3),
        throwsUnsupportedError,
      );
    },
  );

  test('4.4.3 finally failure does not replace a successful value', () async {
    client.addHook(trace('cleanup', [], failure: 'finally'));
    expect(await client.getBooleanValue('flag', defaultValue: false), true);
  });

  test('4.4.5-7 timeout short-circuits before and invokes cleanup', () async {
    final calls = <String>[];
    client.addHook(
      EvaluationHook(
        metadata: const HookMetadata(
          name: 'timeout',
          config: HookConfig(timeout: Duration(milliseconds: 10)),
        ),
        before: (context, hints) => Completer<EvaluationContext?>().future,
        error: (context, error, hints) {
          expect(error, isA<TimeoutException>());
          calls.add('error');
        },
        finallyAfter: (context, details, hints) => calls.add('finally'),
      ),
    );
    expect(await client.getBooleanValue('flag', defaultValue: false), false);
    expect(provider.contexts, isEmpty);
    expect(calls, ['error', 'finally']);
  });

  test(
    '1.3.1.1 / 1.4.1.1 options reach all twenty new and legacy typed methods',
    () async {
      var count = 0;
      final options = EvaluationOptions(
        hooks: [
          EvaluationHook(
            metadata: const HookMetadata(name: 'count'),
            finallyAfter: (context, details, hints) {
              count++;
              expect(hints.hints['trace'], true);
            },
          ),
        ],
        hints: HookHints.immutable({'trace': true}),
      );
      await client.getBooleanValue(
        'flag',
        defaultValue: false,
        options: options,
      );
      await client.getStringValue('string', defaultValue: '', options: options);
      await client.getIntegerValue('int', defaultValue: 0, options: options);
      await client.getDoubleValue('double', defaultValue: 0, options: options);
      await client.getObjectValue('object', defaultValue: {}, options: options);
      await client.getBooleanEvaluationDetails(
        'flag',
        defaultValue: false,
        options: options,
      );
      await client.getStringEvaluationDetails(
        'string',
        defaultValue: '',
        options: options,
      );
      await client.getIntegerEvaluationDetails(
        'int',
        defaultValue: 0,
        options: options,
      );
      await client.getDoubleEvaluationDetails(
        'double',
        defaultValue: 0,
        options: options,
      );
      await client.getObjectEvaluationDetails(
        'object',
        defaultValue: {},
        options: options,
      );
      await client.getBooleanFlag('flag', options: options);
      await client.getStringFlag('string', options: options);
      await client.getIntegerFlag('int', options: options);
      await client.getDoubleFlag('double', options: options);
      await client.getObjectFlag('object', options: options);
      await client.getBooleanDetails('flag', options: options);
      await client.getStringDetails('string', options: options);
      await client.getIntegerDetails('int', options: options);
      await client.getDoubleDetails('double', options: options);
      await client.getObjectDetails('object', options: options);
      expect(count, 20);
    },
  );
  test(
    '4.3.7-8 provider lookup failure still runs registered error/finally hooks',
    () async {
      final lookupClient = FeatureClient(
        metadata: ClientMetadata(name: 'lookup'),
        hookManager: HookManager(),
        defaultContext: EvaluationContext.immutable(),
        providerResolver: () => throw StateError('lookup'),
      );
      addTearDown(lookupClient.dispose);
      final calls = <String>[];
      lookupClient.addHook(trace('client', calls));
      final result = await lookupClient.getBooleanEvaluationDetails(
        'flag',
        defaultValue: true,
        options: EvaluationOptions(hooks: [trace('invocation', calls)]),
      );
      expect(result.value, true);
      expect(result.errorCode, ErrorCode.GENERAL);
      expect(calls, [
        'invocation:error',
        'client:error',
        'invocation:finally',
        'client:finally',
      ]);
    },
  );

  test(
    '4.4.3-7 failing hook metadata cannot suppress remaining cleanup',
    () async {
      final calls = <String>[];
      client.addHooks([trace('observer', calls), BrokenMetadataHook()]);
      expect(await client.getBooleanFlag('flag', defaultValue: false), false);
      expect(calls, ['observer:before', 'observer:error', 'observer:finally']);
    },
  );

  test(
    '4.4.5-7 even an unformattable exception preserves default and cleanup',
    () async {
      final calls = <String>[];
      client.addHook(
        EvaluationHook(
          metadata: const HookMetadata(name: 'broken-error'),
          before: (context, hints) => throw UnformattableError(),
          error: (context, error, hints) => calls.add('error'),
          finallyAfter: (context, details, hints) => calls.add('finally'),
        ),
      );
      expect(await client.getBooleanFlag('flag', defaultValue: false), false);
      expect(calls, ['error', 'finally']);
    },
  );

  for (final stage in ['before', 'after']) {
    for (final type in ['boolean', 'string', 'integer', 'double', 'object']) {
      test(
        '4.3.8 / 4.4.7 $stage failure retains exact $type default',
        () async {
          EvaluationDetails? observed;
          final options = EvaluationOptions(
            hooks: [
              trace('fail', [], failure: stage),
              EvaluationHook(
                metadata: const HookMetadata(name: 'details'),
                finallyAfter: (context, details, hints) {
                  observed = details;
                },
              ),
            ],
          );
          final fallback = switch (type) {
            'boolean' => false,
            'string' => 'fallback',
            'integer' => -12,
            'double' => -1.25,
            _ => <String, dynamic>{'fallback': true},
          };
          final result = switch (type) {
            'boolean' => await client.getBooleanEvaluationDetails(
              'flag',
              defaultValue: fallback as bool,
              options: options,
            ),
            'string' => await client.getStringEvaluationDetails(
              'string',
              defaultValue: fallback as String,
              options: options,
            ),
            'integer' => await client.getIntegerEvaluationDetails(
              'int',
              defaultValue: fallback as int,
              options: options,
            ),
            'double' => await client.getDoubleEvaluationDetails(
              'double',
              defaultValue: fallback as double,
              options: options,
            ),
            _ => await client.getObjectEvaluationDetails(
              'object',
              defaultValue: fallback as Map<String, dynamic>,
              options: options,
            ),
          };
          expect(result.value, same(fallback));
          expect(observed!.value, fallback);
          expect(observed!.errorCode, result.errorCode);
          expect(observed!.reason, result.reason);
          expect(observed!.errorMessage, result.errorMessage);
          expect(observed!.evaluationTime, result.timestamp);
        },
      );
    }
  }
  test('4.4.5-7 legacy exception diagnostics do not prevent cleanup', () async {
    final cause = Object();
    var cleaned = false;
    client.addHook(
      EvaluationHook(
        metadata: const HookMetadata(name: 'diagnostics'),
        before: (context, hints) =>
            throw ProviderException('failure', details: {'cause': cause}),
        finallyAfter: (context, details, hints) {
          cleaned = true;
          expect(details.additionalDetails!['cause'], same(cause));
        },
      ),
    );
    expect(await client.getBooleanFlag('flag', defaultValue: false), false);
    expect(cleaned, true);
  });
}
