import 'package:test/test.dart';
import '../lib/evaluation_context.dart';
import '../lib/open_feature_api.dart';
import '../lib/src/context_snapshot.dart';

enum Plan { paid }

void main() {
  final operands = <String, Object>{
    'enum': Plan.paid,
    'duration': const Duration(seconds: 3),
    'uri': Uri.parse('https://example.com'),
    'object': Object(),
  };
  for (final snapshot in [false, true]) {
    EvaluationContext capture(List<TargetingRule> rules) => snapshot
        ? EvaluationContext(attributes: {}, rules: rules).snapshot()
        : EvaluationContext.immutable(rules: rules);

    group(snapshot ? 'snapshot' : 'immutable', () {
      for (final entry in operands.entries) {
        test('preserves ${entry.key} operands and evaluation', () {
          for (final operator in [
            TargetingOperator.EQUALS,
            TargetingOperator.NOT_EQUALS,
            TargetingOperator.IN_LIST,
            TargetingOperator.NOT_IN_LIST,
            TargetingOperator.CONTAINS,
          ]) {
            final isList =
                operator == TargetingOperator.IN_LIST ||
                operator == TargetingOperator.NOT_IN_LIST;
            final original = TargetingRule(
              'value',
              operator,
              isList ? [entry.value] : entry.value,
            );
            final copied = capture([original]).rules.single;
            expect(
              isList ? copied.value.single : copied.value,
              same(entry.value),
            );
            for (final attribute in [entry.value, 'other']) {
              expect(
                copied.evaluate({'value': attribute}),
                original.evaluate({'value': attribute}),
              );
            }
          }
        });
      }

      test('freezes nested collections and retains arbitrary map keys', () {
        final key = Object();
        final values = <Object?>[Plan.paid, operands['uri'], null];
        final map = <Object?, Object?>{key: values, 42: operands['duration']};
        final source = <Object?>[map, map];
        final copied =
            capture([
                  TargetingRule('value', TargetingOperator.IN_LIST, source),
                ]).rules.single.value
                as List;
        values.clear();
        map.clear();
        source.clear();
        expect(copied, hasLength(2));
        expect(copied[0][key], [Plan.paid, operands['uri'], null]);
        expect(copied[1][42], same(operands['duration']));
        expect(() => copied.clear(), throwsUnsupportedError);
        expect(() => (copied[0] as Map).clear(), throwsUnsupportedError);
        expect(() => (copied[0][key] as List).clear(), throwsUnsupportedError);
      });

      test('snapshots operands in subrules', () {
        final copied = capture([
          TargetingRule(
            'enabled',
            TargetingOperator.EQUALS,
            true,
            subRules: [
              TargetingRule('plan', TargetingOperator.EQUALS, Plan.paid),
            ],
          ),
        ]).rules.single;
        expect(copied.evaluate({'enabled': true, 'plan': Plan.paid}), isTrue);
      });

      test('rejects cyclic operands with the rule value path', () {
        final list = <Object?>[];
        final map = <Object?, Object?>{'nested': list};
        list.add(map);
        expect(
          () => capture([
            TargetingRule('value', TargetingOperator.IN_LIST, list),
          ]),
          throwsA(
            isA<InvalidContextException>().having(
              (error) => error.message,
              'path',
              contains('rules[0].value'),
            ),
          ),
        );
      });
    });
  }

  test(
    'wrapper merge retains both rule lists and the left cache duration',
    () async {
      final api = OpenFeatureAPI();
      addTearDown(OpenFeatureAPI.resetInstance);
      api.setEvaluationContext(
        EvaluationContext(
          targetingKey: 'left',
          attributes: {'left': true, 'shared': 'left'},
          parent: EvaluationContext(attributes: {'inherited': true}),
          rules: [TargetingRule('left', TargetingOperator.EQUALS, true)],
          cacheDuration: const Duration(seconds: 17),
        ),
      );
      final left = api.globalContext!;
      api.setEvaluationContext(
        EvaluationContext(
          targetingKey: 'right',
          attributes: {'right': false, 'shared': 'right'},
          rules: [TargetingRule('right', TargetingOperator.EQUALS, true)],
          cacheDuration: const Duration(seconds: 99),
        ),
      );
      final merged = left.merge(api.globalContext!).toEvaluationContext();
      expect(merged.rules.map((rule) => rule.attribute), ['left', 'right']);
      expect(merged.cacheDuration, const Duration(seconds: 17));
      expect(merged.targetingKey, 'right');
      expect(merged.attributes['shared'], 'right');
      expect(merged.attributes['inherited'], isTrue);
      expect(merged.parent, isNull);
      expect(merged.snapshot(), same(merged));
      expect(await merged.evaluateRules(), isFalse);

      final mixed = left.merge(OpenFeatureEvaluationContext({'extra': true}));
      expect(mixed.toEvaluationContext().rules.single.attribute, 'left');
      expect(
        mixed.toEvaluationContext().cacheDuration,
        const Duration(seconds: 17),
      );
      expect(() => mixed.attributes['extra'] = false, throwsUnsupportedError);
    },
  );
}
