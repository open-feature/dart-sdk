import 'dart:async';
import 'package:test/test.dart';
import '../lib/client.dart';
import '../lib/evaluation_context.dart';
import '../lib/feature_provider.dart';
import '../lib/hooks.dart';
import '../lib/open_feature_api.dart';
import '../lib/transaction_context.dart';

class CapturingProvider extends InMemoryProvider {
  final contexts = <String, Map<String, dynamic>>{};
  CapturingProvider() : super({});

  @override
  ProviderState get state => ProviderState.READY;

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    contexts[flagKey] = context!;
    return FlagEvaluationResult(
      flagKey: flagKey,
      value: true,
      evaluatedAt: DateTime.now(),
      evaluatorId: 'capture',
    );
  }
}

class CallbackHook extends BaseHook {
  final Future<Map<String, dynamic>?> Function(HookContext) callback;
  CallbackHook(this.callback)
    : super(metadata: const HookMetadata(name: 'test'));
  @override
  Future<Map<String, dynamic>?> before(HookContext context) =>
      callback(context);
}

FeatureClient clientFor(
  CapturingProvider provider, {
  EvaluationContext api = const EvaluationContext(attributes: {}),
  EvaluationContext client = const EvaluationContext(attributes: {}),
  HookManager? hooks,
}) => FeatureClient(
  metadata: ClientMetadata(name: 'context-test'),
  hookManager: hooks ?? HookManager(),
  defaultContext: client,
  apiContext: api,
  provider: provider,
);

void main() {
  group('v0.9.0 3.1 fields', () {
    test('3.1.1-4: allowed types, keyed/full access and one targeting key', () {
      final when = DateTime.utc(2026, 9, 15);
      final context = EvaluationContext.immutable(
        targetingKey: 'explicit',
        attributes: {
          'targetingKey': 'legacy',
          'bool': true,
          'string': 'value',
          'int': 4,
          'double': 2.5,
          'when': when,
          'structure': {
            'list': [
              false,
              3,
              null,
              {'nested': when},
            ],
          },
        },
      );
      expect(context.targetingKey, 'explicit');
      expect(context.attributes['targetingKey'], 'explicit');
      expect(context.getAttribute('when'), when);
      expect(context.toProviderContext(), {
        ...context.attributes,
        'targetingKey': 'explicit',
      });
      expect(context.attributes.length, 7);
    });

    test('nested fields are copied and frozen through every accessor', () {
      final nested = <String, dynamic>{'name': 'before'};
      final list = <dynamic>[nested];
      final attributes = <String, dynamic>{'items': list};
      final context = EvaluationContext.immutable(attributes: attributes);
      nested['name'] = 'after';
      list.add(false);
      attributes.clear();
      expect(context.attributes, {
        'items': [
          {'name': 'before'},
        ],
      });
      expect(() => context.attributes['x'] = true, throwsUnsupportedError);
      expect(
        () => (context.getAttribute('items') as List).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => context.toProviderContext()['items'][0]['name'] = 'after',
        throwsUnsupportedError,
      );
    });

    final cyclic = <dynamic>[];
    cyclic.add(cyclic);
    for (final entry in <String, dynamic>{
      'custom object': Object(),
      'function': () {},
      'set': {'x'},
      'non-string map key': {1: 'bad'},
      'cycle': cyclic,
    }.entries) {
      test('3.1.2: rejects ${entry.key} deliberately', () {
        expect(
          () => EvaluationContext.immutable(attributes: {'bad': entry.value}),
          throwsArgumentError,
        );
      });
    }

    test('3.1.1: rejects non-string legacy targeting key', () {
      expect(
        () => EvaluationContext.immutable(
          targetingKey: 'explicit',
          attributes: {'targetingKey': 5},
        ),
        throwsArgumentError,
      );
    });

    test('shared acyclic structures are supported without aliasing', () {
      final shared = {'ok': true};
      final context = EvaluationContext.immutable(
        attributes: {'a': shared, 'b': shared},
      );
      shared['ok'] = false;
      expect(context.attributes, {
        'a': {'ok': true},
        'b': {'ok': true},
      });
    });

    test('parent snapshots and map-form targeting precedence', () {
      final values = {'region': 'original'};
      final parent = EvaluationContext(
        targetingKey: 'parent',
        attributes: values,
      );
      final child = EvaluationContext.immutable(
        parent: parent,
        attributes: {'targetingKey': 'child'},
      );
      values['region'] = 'changed';
      expect(child.toProviderContext(), {
        'region': 'original',
        'targetingKey': 'child',
      });
      expect(child.getAttribute('region'), 'original');
    });
  });

  group('v0.9.0 3.2.3 merging and runtime isolation', () {
    tearDown(() => TransactionContextManager().cleanup());

    for (var highest = 0; highest < 5; highest++) {
      test(
        'context precedence through level $highest including targeting',
        () async {
          Map<String, dynamic> fields(int level) => {
            'shared': level,
            'only$level': true,
            'targetingKey': 'subject$level',
          };
          final provider = CapturingProvider();
          final hooks = HookManager();
          if (highest == 4) {
            hooks.addHook(CallbackHook((_) async => fields(4)));
          }
          final client = clientFor(
            provider,
            api: EvaluationContext.immutable(attributes: fields(0)),
            client: EvaluationContext.immutable(
              attributes: highest >= 2 ? fields(2) : {},
            ),
            hooks: hooks,
          );
          addTearDown(client.dispose);
          await TransactionContextManager().withContext(
            'request',
            highest >= 1 ? fields(1) : {},
            () async {
              expect(
                await client.getBooleanFlag(
                  'flag',
                  defaultValue: false,
                  context: EvaluationContext.immutable(
                    attributes: highest >= 3 ? fields(3) : {},
                  ),
                ),
                isTrue,
              );
            },
          );
          expect(provider.contexts['flag'], {
            for (var i = 0; i <= highest; i++) 'only$i': true,
            'shared': highest,
            'targetingKey': 'subject$highest',
          });
        },
      );
    }

    test('explicit snapshots isolate client/api maps', () async {
      final apiData = {'value': 'api-before'};
      final clientData = {'value': 'client-before'};
      final provider = CapturingProvider();
      final client = clientFor(
        provider,
        api: EvaluationContext.immutable(attributes: {'api': apiData}),
        client: EvaluationContext.immutable(attributes: {'client': clientData}),
      );
      addTearDown(client.dispose);
      apiData['value'] = 'after';
      clientData['value'] = 'after';
      await client.getBooleanFlag('flag');
      expect(provider.contexts['flag'], {
        'api': {'value': 'api-before'},
        'client': {'value': 'client-before'},
      });
    });

    test(
      'explicit invocation snapshot survives an awaited before hook',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final provider = CapturingProvider();
        final hooks = HookManager()
          ..addHook(
            CallbackHook((context) async {
              expect(
                () => context.evaluationContext['nested']['tier'] = 'changed',
                throwsUnsupportedError,
              );
              entered.complete();
              await release.future;
              return null;
            }),
          );
        final client = clientFor(provider, hooks: hooks);
        addTearDown(client.dispose);
        final nested = {'tier': 'before'};
        final result = client.getBooleanFlag(
          'flag',
          context: EvaluationContext.immutable(attributes: {'nested': nested}),
        );
        await entered.future;
        nested['tier'] = 'after';
        release.complete();
        expect(await result, isTrue);
        expect(provider.contexts['flag']!['nested'], {'tier': 'before'});
      },
    );

    test('before hooks can explicitly snapshot returned fields', () async {
      final nested = {'source': 'first'};
      final hooks = HookManager()
        ..addHook(
          CallbackHook(
            (_) async => EvaluationContext.immutable(
              attributes: {'nested': nested},
            ).attributes,
          ),
        )
        ..addHook(
          CallbackHook((context) async {
            nested['source'] = 'changed';
            expect(context.evaluationContext['nested']['source'], 'first');
            return null;
          }),
        );
      final provider = CapturingProvider();
      final client = clientFor(provider, hooks: hooks);
      addTearDown(client.dispose);
      expect(await client.getBooleanFlag('flag'), isTrue);
      expect(provider.contexts['flag']!['nested']['source'], 'first');
      expect(
        () => provider.contexts['flag']!['nested']['source'] = 'mutated',
        throwsUnsupportedError,
      );
    });

    test('explicit invalid hook snapshots report INVALID_CONTEXT', () async {
      final provider = CapturingProvider();
      final client = clientFor(provider);
      addTearDown(client.dispose);
      client.addHook(
        CallbackHook(
          (_) async => EvaluationContext.immutable(
            attributes: {
              'account': {'bad': Object()},
            },
          ).attributes,
        ),
      );
      final result = await client.getBooleanDetails(
        'hook',
        defaultValue: false,
      );
      expect(result.value, isFalse);
      expect(result.errorCode, ErrorCode.INVALID_CONTEXT);
      expect(result.errorMessage, contains('attributes.account.bad'));
      expect(provider.contexts, isEmpty);
    });

    test(
      '3.3: overlapping transactions retain their own nested values',
      () async {
        final manager = TransactionContextManager();
        final provider = CapturingProvider();
        final client = clientFor(provider);
        addTearDown(client.dispose);
        final firstEntered = Completer<void>();
        final secondEntered = Completer<void>();
        final a = {'role': 'a'};
        final b = {'role': 'b'};
        await Future.wait([
          manager.withContext(
            'a',
            EvaluationContext.immutable(attributes: {'user': a}).attributes,
            () async {
              firstEntered.complete();
              await secondEntered.future;
              a['role'] = 'mutated';
              await client.getBooleanFlag('a');
            },
          ),
          manager.withContext(
            'b',
            EvaluationContext.immutable(attributes: {'user': b}).attributes,
            () async {
              await firstEntered.future;
              secondEntered.complete();
              b['role'] = 'mutated';
              await client.getBooleanFlag('b');
            },
          ),
        ]);
        expect(provider.contexts['a']!['user']['role'], 'a');
        expect(provider.contexts['b']!['user']['role'], 'b');
        expect(manager.currentContext, isNull);
      },
    );

    test(
      'existing API clients observe later canonical global snapshots',
      () async {
        final api = OpenFeatureAPI();
        addTearDown(OpenFeatureAPI.resetInstance);
        final provider = CapturingProvider();
        await api.setProviderAndWait(provider);
        final client = api.getClient('existing');
        addTearDown(client.dispose);
        api.setGlobalContext(OpenFeatureEvaluationContext({'version': 1}));
        await client.getBooleanFlag('before');
        final next = {'number': 2};
        api.setEvaluationContext(
          EvaluationContext(attributes: {'version': next}),
        );
        next['number'] = 3;
        await client.getBooleanFlag('after');
        expect(provider.contexts['before']!['version'], 1);
        expect(provider.contexts['after']!['version'], {'number': 2});
        expect(
          api.evaluationContext!.attributes,
          api.globalContext!.attributes,
        );
      },
    );
  });
}
