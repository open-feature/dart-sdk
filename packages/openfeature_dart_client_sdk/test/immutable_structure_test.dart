import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('context accepts null and repeated acyclic structures', () {
    final shared = {
      'x': [1, null],
    };
    final context = EvaluationContext(
      attributes: {'null': null, 'a': shared, 'b': shared},
    );
    (shared['x'] as List).clear();
    expect(context.attributes['a'], {
      'x': [1, null],
    });
    expect(context.attributes['b'], context.attributes['a']);
  });
  test('cyclic contexts fail with their path instead of overflowing', () {
    final list = <Object?>[];
    list.add(list);
    expect(
      () => EvaluationContext(
        attributes: {
          'account': {'orders': list},
        },
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'path',
          contains('attributes.account.orders[0]'),
        ),
      ),
    );
  });
  test('unsupported values include paths without printing values', () {
    expect(
      () => EvaluationContext(
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
  });
}
