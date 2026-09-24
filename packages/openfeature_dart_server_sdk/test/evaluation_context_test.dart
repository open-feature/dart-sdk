import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';

void main() {
  group('TargetingRule', () {
    test('evaluates EQUALS operator', () {
      final rule = TargetingRule('role', TargetingOperator.EQUALS, 'admin');
      expect(rule.evaluate({'role': 'admin'}), isTrue);
      expect(rule.evaluate({'role': 'user'}), isFalse);
    });

    test('evaluates IN_LIST operator', () {
      final rule = TargetingRule('role', TargetingOperator.IN_LIST, [
        'admin',
        'superuser',
      ]);
      expect(rule.evaluate({'role': 'admin'}), isTrue);
      expect(rule.evaluate({'role': 'user'}), isFalse);
    });

    test('evaluates CONTAINS operator', () {
      final rule = TargetingRule('name', TargetingOperator.CONTAINS, 'john');
      expect(rule.evaluate({'name': 'john doe'}), isTrue);
      expect(rule.evaluate({'name': 'jane doe'}), isFalse);
    });

    test('evaluates nested rules', () {
      final rule = TargetingRule(
        'role',
        TargetingOperator.EQUALS,
        'admin',
        subRules: [TargetingRule('region', TargetingOperator.EQUALS, 'EU')],
      );

      expect(rule.evaluate({'role': 'admin', 'region': 'EU'}), isTrue);
      expect(rule.evaluate({'role': 'admin', 'region': 'US'}), isFalse);
    });
  });

  group('EvaluationContext', () {
    test(
      'provider context preserves inherited targeting key and attributes',
      () {
        final parent = EvaluationContext(
          targetingKey: 'parent-user',
          attributes: {'region': 'us', 'shared': 'parent'},
        );
        final child = parent.createChild({'shared': 'child'});

        expect(
          child.toProviderContext(),
          equals({
            'region': 'us',
            'shared': 'child',
            'targetingKey': 'parent-user',
          }),
        );
      },
    );

    test('retrieves attributes from parent context', () {
      final parent = EvaluationContext(
        attributes: {'env': 'prod', 'shared': 'parent'},
      );

      final child = EvaluationContext(
        attributes: {'region': 'EU', 'shared': 'child'},
        parent: parent,
      );

      expect(child.getAttribute('env'), equals('prod'));
      expect(child.getAttribute('region'), equals('EU'));
      expect(child.getAttribute('shared'), equals('child'));
    });

    test('merges contexts correctly', () {
      final context1 = EvaluationContext(
        attributes: {'key1': 'value1'},
        rules: [TargetingRule('test1', TargetingOperator.EQUALS, 'value1')],
      );

      final context2 = EvaluationContext(
        attributes: {'key2': 'value2'},
        rules: [TargetingRule('test2', TargetingOperator.EQUALS, 'value2')],
      );

      final merged = context1.merge(context2);
      expect(merged.attributes['key1'], equals('value1'));
      expect(merged.attributes['key2'], equals('value2'));
      expect(merged.rules.length, equals(2));
    });

    test('evaluates rules in context hierarchy', () async {
      final parent = EvaluationContext(
        attributes: {'env': 'prod'},
        rules: [TargetingRule('env', TargetingOperator.EQUALS, 'prod')],
      );

      final child = EvaluationContext(
        attributes: {'region': 'EU'},
        rules: [TargetingRule('region', TargetingOperator.EQUALS, 'EU')],
        parent: parent,
      );

      expect(await parent.evaluateRules(), isTrue);
      expect(await child.evaluateRules(), isTrue);
    });

    test('creates child context correctly', () {
      final parent = EvaluationContext(
        attributes: {'env': 'prod'},
        cacheDuration: Duration(minutes: 10),
      );

      final child = parent.createChild(
        {'region': 'EU'},
        childRules: [TargetingRule('region', TargetingOperator.EQUALS, 'EU')],
      );

      expect(child.parent, equals(parent));
      expect(child.attributes['region'], equals('EU'));
      expect(child.rules.length, equals(1));
      expect(child.cacheDuration, equals(parent.cacheDuration));
    });
  });
}
