import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/transaction_context.dart';

void main() {
  group('TransactionContext', () {
    test('merges attributes with parent context', () {
      final parent = TransactionContext(
        transactionId: 'parent',
        attributes: {'shared': 'parent', 'parentOnly': 'value'},
      );

      final child = TransactionContext(
        transactionId: 'child',
        attributes: {'shared': 'child', 'childOnly': 'value'},
        parent: parent,
      );

      final effective = child.effectiveAttributes;
      expect(effective['shared'], equals('child'));
      expect(effective['parentOnly'], equals('value'));
      expect(effective['childOnly'], equals('value'));
    });

    test('handles cleanup timer', () async {
      final context = TransactionContext(transactionId: 'test', attributes: {});

      context.scheduleCleanup(Duration(milliseconds: 100));
      await Future.delayed(Duration(milliseconds: 150));

      expect(context.cleanup, isNot(throwsException));
    });
  });

  group('TransactionContextManager', () {
    late TransactionContextManager manager;

    setUp(() {
      manager = TransactionContextManager();
    });

    tearDown(() {
      manager.cleanup();
    });

    test('maintains context stack', () {
      final context1 = TransactionContext(
        transactionId: 'tx1',
        attributes: {'key1': 'value1'},
      );

      final context2 = TransactionContext(
        transactionId: 'tx2',
        attributes: {'key2': 'value2'},
      );

      manager.pushContext(context1);
      manager.pushContext(context2);

      expect(manager.currentContext, equals(context2));

      final popped = manager.popContext();
      expect(popped, equals(context2));
      expect(manager.currentContext, equals(context1));
    });

    test('executes with context', () async {
      var executedWithContext = false;

      await manager.withContext('tx', {'key': 'value'}, () async {
        expect(manager.currentContext?.attributes['key'], equals('value'));
        executedWithContext = true;
        // Ensure context is popped after execution
        await Future.delayed(Duration.zero);
      });

      expect(executedWithContext, isTrue);
      await Future.delayed(Duration.zero); // Allow context cleanup
      expect(manager.currentContext, isNull);
    });

    test('isolates async contexts across overlapping operations', () async {
      final seen = <String>[];

      await Future.wait([
        manager.withContext('tx-a', {'requestId': 'a'}, () async {
          await Future.delayed(const Duration(milliseconds: 20));
          seen.add(manager.currentContext?.attributes['requestId'] as String);
        }),
        manager.withContext('tx-b', {'requestId': 'b'}, () async {
          await Future.delayed(const Duration(milliseconds: 5));
          seen.add(manager.currentContext?.attributes['requestId'] as String);
        }),
      ]);

      expect(seen.toSet(), equals({'a', 'b'}));
      expect(manager.currentContext, isNull);
    });

    test('creates child context', () {
      final parent = TransactionContext(
        transactionId: 'parent',
        attributes: {'parent': 'value'},
      );

      manager.pushContext(parent);

      final child = manager.createChildContext('child', {'child': 'value'});

      expect(child.parent, equals(parent));
      expect(child.effectiveAttributes['parent'], equals('value'));
      expect(child.effectiveAttributes['child'], equals('value'));
    });

    test('cleans up all contexts', () {
      manager.pushContext(
        TransactionContext(transactionId: 'tx1', attributes: {}),
      );

      manager.pushContext(
        TransactionContext(transactionId: 'tx2', attributes: {}),
      );

      manager.cleanup();
      expect(manager.currentContext, isNull);
    });
  });
}
