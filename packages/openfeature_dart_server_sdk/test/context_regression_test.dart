import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/transaction_context.dart';

void main() {
  test('explicit context snapshots nested caller data', () {
    final nested = {'tier': 'standard'};
    final context = EvaluationContext.immutable(
      attributes: {'account': nested},
    );
    nested['tier'] = 'premium';
    expect(context.attributes['account']['tier'], 'standard');
  });

  test('transaction accepts explicitly snapshotted caller data', () {
    final groups = ['first'];
    final context = TransactionContext(
      transactionId: 'request',
      attributes: EvaluationContext.immutable(
        attributes: {'groups': groups},
      ).attributes,
    );
    groups.add('second');
    expect(context.effectiveAttributes['groups'], ['first']);
  });

  test('merge preserves both complete parent chains', () {
    const left = EvaluationContext(
      attributes: {},
      parent: EvaluationContext(
        attributes: {},
        parent: EvaluationContext(attributes: {'left': true}),
      ),
    );
    const right = EvaluationContext(
      attributes: {},
      parent: EvaluationContext(
        targetingKey: 'right',
        attributes: {'right': true},
      ),
    );
    expect(left.merge(right).toProviderContext(), {
      'left': true,
      'right': true,
      'targetingKey': 'right',
    });
  });
}
