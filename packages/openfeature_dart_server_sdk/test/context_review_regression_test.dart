import 'dart:async';
import 'package:test/test.dart';
import '../lib/client.dart';
import '../lib/evaluation_context.dart';
import '../lib/feature_provider.dart';
import '../lib/hooks.dart';
import '../lib/open_feature_api.dart';
import '../lib/transaction_context.dart';

enum Plan { paid }

class CompatibilityProvider extends InMemoryProvider {
  Map<String, dynamic>? evaluated;
  Map<String, dynamic>? tracked;
  bool stamp = false;
  CompatibilityProvider() : super({});
  @override
  ProviderState get state => ProviderState.READY;
  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    if (stamp) context!['provider'] = 'stamped';
    if (context!.containsKey('groups')) {
      expect(context['groups'] as List<String>, ['a', 'b']);
      expect(context['counts'] as Map<String, int>, {'a': 1});
    }
    evaluated = context;
    return FlagEvaluationResult(
      flagKey: flagKey,
      value: true,
      evaluatedAt: DateTime.now(),
      evaluatorId: 'compatibility',
    );
  }

  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    if (stamp) evaluationContext!['provider'] = 'stamped';
    tracked = evaluationContext;
  }
}

class LegacyHook extends BaseHook {
  final Map<String, dynamic> updates;
  LegacyHook(this.updates)
    : super(metadata: const HookMetadata(name: 'legacy'));
  @override
  Future<Map<String, dynamic>?> before(HookContext context) async => updates;
}

void main() {
  late CompatibilityProvider provider;
  late FeatureClient client;
  setUp(() {
    provider = CompatibilityProvider();
    client = FeatureClient(
      metadata: ClientMetadata(name: 'compatibility'),
      hookManager: HookManager(),
      defaultContext: const EvaluationContext(attributes: {}),
      provider: provider,
    );
  });
  tearDown(() async {
    await client.dispose();
    TransactionContextManager().cleanup();
  });

  final values = <String, dynamic>{
    'null': null,
    'duration': const Duration(seconds: 3),
    'uri': Uri.parse('https://example.com'),
    'enum': Plan.paid,
    'bigint': BigInt.parse('12345678901234567890'),
    'iterable': [1, 2].map((n) => n * 2),
    'object': Object(),
    'groups': <String>['a', 'b'],
    'counts': <String, int>{'a': 1},
    'nestedTyped': <String, List<Map<String, int>>>{
      'a': [
        {'b': 2},
      ],
    },
  };
  for (final entry in values.entries) {
    test('legacy evaluation and tracking retain ${entry.key}', () async {
      final fields = {
        entry.key: entry.value,
        if (entry.key == 'groups') 'counts': values['counts'],
      };
      final context = EvaluationContext(attributes: fields);
      final result = await client.getBooleanDetails(
        'f',
        defaultValue: false,
        context: context,
      );
      expect(result.value, isTrue);
      expect(result.errorCode, isNull);
      expect(identical(provider.evaluated![entry.key], entry.value), isTrue);
      await client.track('evt', context: context);
      expect(identical(provider.tracked![entry.key], entry.value), isTrue);
      expect(fields.containsKey('provider'), isFalse);
    });
  }

  test('legacy providers can stamp evaluation and tracking maps', () async {
    provider.stamp = true;
    final attributes = {'plan': 'paid'};
    final context = EvaluationContext(attributes: attributes);
    final result = await client.getBooleanDetails('stamp', context: context);
    expect(result.value, isTrue);
    expect(result.errorCode, isNull);
    expect(provider.evaluated!['provider'], 'stamped');
    await client.track('stamp', context: context);
    expect(provider.tracked!['provider'], 'stamped');
    expect(attributes, {'plan': 'paid'});
  });
  test(
    'legacy tracking independently delivers null and typed values',
    () async {
      await client.track('evt', context: EvaluationContext(attributes: values));
      expect(provider.tracked, isNotNull);
      for (final entry in values.entries) {
        expect(identical(provider.tracked![entry.key], entry.value), isTrue);
      }
    },
  );

  test(
    'legacy API, client, transaction, invocation and hook fields survive',
    () async {
      final api = OpenFeatureAPI();
      addTearDown(OpenFeatureAPI.resetInstance);
      await api.setProviderAndWait(provider);
      api.setGlobalContext(OpenFeatureEvaluationContext({'api': values}));
      final globalClient = api.getClient('global');
      addTearDown(globalClient.dispose);
      await globalClient.getBooleanFlag('global');
      expect(identical(provider.evaluated!['api'], values), isTrue);
      final custom = FeatureClient(
        metadata: ClientMetadata(name: 'all-levels'),
        hookManager: HookManager()..addHook(LegacyHook({'hook': values})),
        defaultContext: EvaluationContext(attributes: {'client': values}),
        apiContext: EvaluationContext(attributes: {'api': values}),
        provider: provider,
      );
      addTearDown(custom.dispose);
      await TransactionContextManager().withContext(
        'request',
        {'transaction': values},
        () async {
          final result = await custom.getBooleanDetails(
            'all',
            defaultValue: false,
            context: EvaluationContext(attributes: {'invocation': values}),
          );
          expect(result.value, isTrue);
          expect(result.errorCode, isNull);
        },
      );
      for (final level in [
        'api',
        'transaction',
        'client',
        'invocation',
        'hook',
      ]) {
        expect(identical(provider.evaluated![level], values), isTrue);
      }
    },
  );

  test('local targeting key wins over the other inherited targeting key', () {
    final left = EvaluationContext(targetingKey: 'mine', attributes: {});
    final right = EvaluationContext(
      attributes: {},
      parent: EvaluationContext(
        targetingKey: 'parentOfOther',
        attributes: {'inherited': true},
      ),
    );
    for (final merged in [
      left.merge(right),
      left.snapshot().merge(right.snapshot()),
    ]) {
      expect(merged.targetingKey, 'mine');
      expect(merged.toProviderContext()['targetingKey'], 'mine');
      expect(merged.getAttribute('inherited'), isTrue);
    }
    expect(
      left
          .merge(EvaluationContext(targetingKey: 'theirs', attributes: {}))
          .targetingKey,
      'theirs',
    );
  });

  test(
    'legacy adapter retains targetingKey attributes and explicit precedence',
    () {
      final context = OpenFeatureEvaluationContext({
        'targetingKey': 'u1',
        'x': 1,
      });
      expect(context.attributes['targetingKey'], 'u1');
      expect(context.toEvaluationContext().getAttribute('targetingKey'), 'u1');
      final merged = OpenFeatureEvaluationContext(
        {'targetingKey': 'old'},
        targetingKey: 'mine',
      ).merge(OpenFeatureEvaluationContext({'targetingKey': 'u1'}));
      expect(
        merged.toEvaluationContext().toProviderContext()['targetingKey'],
        'mine',
      );
      expect(() => merged.attributes['x'] = 2, throwsUnsupportedError);
    },
  );

  test(
    'explicit snapshots accept top-level null and cache the flattened map',
    () {
      final context = EvaluationContext.immutable(
        attributes: {'plan': null},
        parent: EvaluationContext.immutable(
          attributes: {
            'account': {'id': 'u1'},
          },
        ),
      );
      expect(context.attributes.containsKey('plan'), isTrue);
      expect(context.snapshot(), same(context));
      expect(context.toProviderContext(), same(context.toProviderContext()));
    },
  );

  test('immutable createChild snapshots caller attributes and rules', () async {
    final values = <String>['admin'];
    final metadata = {
      'nested': {'source': 'before'},
    };
    final children = <TargetingRule>[];
    final rule = TargetingRule(
      'role',
      TargetingOperator.IN_LIST,
      values,
      metadata: metadata,
      subRules: children,
    );
    final fields = {'role': 'admin'};
    final child = EvaluationContext.immutable(
      attributes: {},
    ).createChild(fields, childRules: [rule]);
    fields['role'] = 'user';
    values.clear();
    metadata['nested']!['source'] = 'after';
    children.add(TargetingRule('role', TargetingOperator.EQUALS, 'nobody'));
    expect(await child.evaluateRules(), isTrue);
    expect(child.rules.first.metadata!['nested']['source'], 'before');
    expect(() => child.attributes['role'] = 'changed', throwsUnsupportedError);
    expect(
      () => (child.rules.first.value as List).clear(),
      throwsUnsupportedError,
    );
    expect(() => child.rules.first.subRules.clear(), throwsUnsupportedError);
  });

  test('immutable validation reports paths and rejects rule cycles', () {
    expect(
      () => EvaluationContext.immutable(
        attributes: {
          'account': {
            'orders': [
              {'total': Object()},
            ],
          },
        },
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'path',
          contains('attributes.account.orders[0].total'),
        ),
      ),
    );
    final rules = <TargetingRule>[];
    rules.add(
      TargetingRule('role', TargetingOperator.EQUALS, 'admin', subRules: rules),
    );
    expect(
      () => EvaluationContext.immutable(rules: rules),
      throwsArgumentError,
    );
  });
}
