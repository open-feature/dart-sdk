import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:openfeature_dart_server_sdk/logging.dart';

void main() {
  group('StructuredLogEntry', () {
    test('creates with required fields', () {
      final entry = StructuredLogEntry(
        level: Level.INFO,
        message: 'Test message',
        timestamp: DateTime.now(),
      );
      expect(entry.context, isEmpty);
      expect(entry.error, isNull);
      expect(entry.stackTrace, isNull);
    });

    test('converts to JSON correctly', () {
      final timestamp = DateTime.now();
      final entry = StructuredLogEntry(
        level: Level.SEVERE,
        message: 'Error message',
        timestamp: timestamp,
        context: {'key': 'value'},
        error: 'Test error',
        stackTrace: StackTrace.current,
      );

      final json = entry.toJson();
      expect(json['level'], equals('SEVERE'));
      expect(json['message'], equals('Error message'));
      expect(json['timestamp'], equals(timestamp.toIso8601String()));
      expect(json['context']['key'], equals('value'));
      expect(json['error'], equals('Test error'));
      expect(json['stackTrace'], isNotNull);
    });
  });

  group('DefaultLogger', () {
    test('creates singleton instance per name', () {
      final logger1 = DefaultLogger('test');
      final logger2 = DefaultLogger('test');
      expect(identical(logger1, logger2), isTrue);
    });

    test('respects logging level', () {
      final logger = DefaultLogger('test');
      Logger.root.level = Level.WARNING;
      expect(logger.isLevelEnabled(Level.INFO), isFalse);
      expect(logger.isLevelEnabled(Level.SEVERE), isTrue);
    });
  });

  group('LoggerFactory', () {
    test('throws when no configuration found', () {
      expect(() => LoggerFactory.getLogger('unknown'), throwsStateError);
    });

    test('configures logger with custom handler', () {
      final entries = <StructuredLogEntry>[];
      LoggerFactory.configure(
        'test',
        LoggerConfig(
          level: Level.INFO,
          customHandler: (entry) => entries.add(entry),
        ),
      );

      final logger = LoggerFactory.getLogger('test');
      final testEntry = StructuredLogEntry(
        level: Level.INFO,
        message: 'Test',
        timestamp: DateTime.now(),
      );
      logger.log(testEntry);

      expect(entries.length, equals(1));
      expect(entries.first.message, equals('Test'));
    });
  });
}
