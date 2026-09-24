import 'dart:async';
import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';

class BrokenStringify {
  @override
  String toString() => throw StateError('broken toString');
}

class TestHook implements Hook {
  final List<String> executionOrder = [];
  final HookPriority _priority;
  bool receivedEvaluationDetails = false;
  HookData? beforeHookData;
  HookData? afterHookData;
  final Map<String, dynamic>? _beforeUpdates;

  TestHook([this._priority = HookPriority.NORMAL, this._beforeUpdates]);

  @override
  HookMetadata get metadata =>
      HookMetadata(name: 'TestHook', priority: _priority);

  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    beforeHookData = context.hookData;
    context.hookData.set('fromBefore', true);
    executionOrder.add('before');
    return _beforeUpdates;
  }

  @override
  Future<void> after(HookContext context) async {
    afterHookData = context.hookData;
    executionOrder.add('after');
  }

  @override
  Future<void> error(HookContext context) async {
    executionOrder.add('error');
  }

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? evaluationDetails, [
    HookHints? hints,
  ]) async {
    executionOrder.add('finally');
    if (evaluationDetails != null) {
      receivedEvaluationDetails = true;
    }
    if (hints != null) {
      executionOrder.add('with_hints');
    }
  }
}

class NamedHook extends BaseHook {
  final String name;
  final List<String> calls;

  NamedHook(this.name, this.calls, HookPriority priority)
    : super(
        metadata: HookMetadata(name: name, priority: priority),
      );

  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    calls.add('before:$name');
    return null;
  }

  @override
  Future<void> after(HookContext context) async {
    calls.add('after:$name');
  }

  @override
  Future<void> error(HookContext context) async {
    calls.add('error:$name');
  }

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? evaluationDetails, [
    HookHints? hints,
  ]) async {
    calls.add('finally:$name');
  }
}

class ThrowingHook extends BaseHook {
  final List<String> calls;
  final String stageToThrow;
  final String name;
  final HookPriority priority;

  ThrowingHook({
    required this.calls,
    required this.stageToThrow,
    required this.name,
    this.priority = HookPriority.NORMAL,
  }) : super(
         metadata: HookMetadata(name: name, priority: priority),
       );

  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    calls.add('before:$name');
    if (stageToThrow == 'before') {
      throw Exception('before failed');
    }
    return null;
  }

  @override
  Future<void> after(HookContext context) async {
    calls.add('after:$name');
    if (stageToThrow == 'after') {
      throw Exception('after failed');
    }
  }

  @override
  Future<void> error(HookContext context) async {
    calls.add('error:$name');
    if (stageToThrow == 'error') {
      throw Exception('error failed');
    }
  }

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? evaluationDetails, [
    HookHints? hints,
  ]) async {
    calls.add('finally:$name');
    if (stageToThrow == 'finally') {
      throw Exception('finally failed');
    }
  }
}

class OTelTestHook extends OpenTelemetryHook {
  final List<Map<String, dynamic>> capturedAttributes = [];

  OTelTestHook({required String providerName})
    : super(
        providerName: providerName,
        telemetryCallback: null, // We'll override the finally_ method
      );

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? evaluationDetails, [
    HookHints? hints,
  ]) async {
    final otelAttributes = evaluationDetails != null
        ? OpenTelemetryUtil.fromEvaluationDetails(
            evaluationDetails,
            providerName: providerName,
          )
        : OpenTelemetryUtil.fromHookContext(
            context,
            providerName: providerName,
          );

    capturedAttributes.add(otelAttributes.toJson());
  }
}

void main() {
  group('HookManager', () {
    late HookManager manager;
    late TestHook testHook;

    setUp(() {
      manager = HookManager();
      testHook = TestHook();
      manager.addHook(testHook);
    });

    test('executes hooks in correct order', () async {
      await manager.executeHooks(HookStage.BEFORE, 'test-flag', {
        'user': 'test',
      });

      await manager.executeHooks(HookStage.AFTER, 'test-flag', {
        'user': 'test',
      }, result: true);

      await manager.executeHooks(HookStage.FINALLY, 'test-flag', {
        'user': 'test',
      });

      expect(testHook.executionOrder, ['before', 'after', 'finally']);
    });

    test('passes evaluation details to finally hook', () async {
      final evaluationDetails = EvaluationDetails(
        flagKey: 'test-flag',
        value: true,
        evaluationTime: DateTime.now(),
        reason: 'TARGETING_MATCH',
        variant: 'control',
      );

      await manager.executeHooks(HookStage.FINALLY, 'test-flag', {
        'user': 'test',
      }, evaluationDetails: evaluationDetails);

      expect(testHook.receivedEvaluationDetails, isTrue);
    });

    test('passes hook hints to finally hook', () async {
      final hints = HookHints(hints: {'source': 'test'});

      await manager.executeHooks(HookStage.FINALLY, 'test-flag', {
        'user': 'test',
      }, hints: hints);

      expect(testHook.executionOrder, contains('with_hints'));
    });

    test('shares hook data across stages when provided', () async {
      final sharedHookData = HookData();

      await manager.executeHooks(HookStage.BEFORE, 'test-flag', {
        'user': 'test',
      }, hookData: sharedHookData);

      await manager.executeHooks(
        HookStage.AFTER,
        'test-flag',
        {'user': 'test'},
        result: true,
        hookData: sharedHookData,
      );

      expect(
        identical(testHook.beforeHookData, testHook.afterHookData),
        isTrue,
      );
      expect(testHook.afterHookData?.get('fromBefore'), isTrue);
    });

    test('runs after, error, and finally hooks in reverse order', () async {
      final calls = <String>[];
      final first = NamedHook('first', calls, HookPriority.HIGH);
      final second = NamedHook('second', calls, HookPriority.LOW);
      manager
        ..addHook(first)
        ..addHook(second);

      await manager.executeHooks(
        HookStage.AFTER,
        'test-flag',
        {},
        result: true,
      );
      await manager.executeHooks(
        HookStage.ERROR,
        'test-flag',
        {},
        error: Exception('boom'),
      );
      await manager.executeHooks(HookStage.FINALLY, 'test-flag', {});

      expect(
        calls,
        equals([
          'after:second',
          'after:first',
          'error:second',
          'error:first',
          'finally:second',
          'finally:first',
        ]),
      );
    });

    test('before hooks can contribute merged evaluation context', () async {
      final mergingHook = TestHook(HookPriority.NORMAL, {
        'hook': 'value',
        'user': 'hook-user',
      });
      manager.addHook(mergingHook);

      final mergedContext = await manager.executeHooks(
        HookStage.BEFORE,
        'test-flag',
        {'user': 'invocation-user', 'region': 'us'},
      );

      expect(mergedContext['region'], equals('us'));
      expect(mergedContext['hook'], equals('value'));
      expect(mergedContext['user'], equals('hook-user'));
    });

    test('before and after failures stop the rest of that stage', () async {
      final calls = <String>[];
      manager
        ..addHook(
          ThrowingHook(
            calls: calls,
            stageToThrow: 'before',
            name: 'first',
            priority: HookPriority.HIGH,
          ),
        )
        ..addHook(NamedHook('second', calls, HookPriority.LOW));

      expect(
        () => manager.executeHooks(HookStage.BEFORE, 'test-flag', {}),
        throwsException,
      );
      expect(calls, equals(['before:first']));
    });

    test('error and finally failures do not stop remaining hooks', () async {
      final calls = <String>[];
      manager
        ..addHook(
          ThrowingHook(
            calls: calls,
            stageToThrow: 'error',
            name: 'first',
            priority: HookPriority.HIGH,
          ),
        )
        ..addHook(NamedHook('second', calls, HookPriority.LOW));

      await manager.executeHooks(
        HookStage.ERROR,
        'test-flag',
        {},
        error: Exception('boom'),
      );

      expect(calls, equals(['error:second', 'error:first']));

      calls.clear();
      final finallyManager = HookManager()
        ..addHook(
          ThrowingHook(
            calls: calls,
            stageToThrow: 'finally',
            name: 'first',
            priority: HookPriority.HIGH,
          ),
        )
        ..addHook(NamedHook('second', calls, HookPriority.LOW));

      await finallyManager.executeHooks(HookStage.FINALLY, 'test-flag', {});
      expect(calls, equals(['finally:second', 'finally:first']));
    });

    test('hook data is isolated per hook instance', () async {
      final first = TestHook(HookPriority.HIGH, {'hookId': 'first'});
      final second = TestHook(HookPriority.LOW, {'hookId': 'second'});
      manager
        ..addHook(first)
        ..addHook(second);

      final sharedHookData = HookData();
      final mergedContext = await manager.executeHooks(
        HookStage.BEFORE,
        'test-flag',
        {'user': 'test'},
        hookData: sharedHookData,
      );

      await manager.executeHooks(
        HookStage.AFTER,
        'test-flag',
        mergedContext,
        result: true,
        hookData: sharedHookData,
      );

      expect(identical(first.beforeHookData, second.beforeHookData), isFalse);
      expect(identical(first.afterHookData, second.afterHookData), isFalse);
      expect(identical(first.beforeHookData, first.afterHookData), isTrue);
      expect(identical(second.beforeHookData, second.afterHookData), isTrue);
    });
  });

  group('OpenTelemetryUtil', () {
    test('creates attributes for boolean flag', () {
      final attributes = OpenTelemetryUtil.createOTelAttributes(
        flagKey: 'test-flag',
        value: true,
        providerName: 'test-provider',
      );

      final jsonMap = attributes.toJson();

      expect(jsonMap[OTelFeatureFlagConstants.FLAG_KEY], equals('test-flag'));
      expect(
        jsonMap[OTelFeatureFlagConstants.FLAG_PROVIDER_NAME],
        equals('test-provider'),
      );
      expect(jsonMap[OTelFeatureFlagConstants.FLAG_EVALUATED], isTrue);
      expect(
        jsonMap[OTelFeatureFlagConstants.FLAG_VALUE_TYPE],
        equals(OTelFeatureFlagConstants.TYPE_BOOLEAN),
      );
      expect(jsonMap[OTelFeatureFlagConstants.FLAG_VALUE_BOOLEAN], isTrue);
      expect(
        jsonMap[OTelFeatureFlagConstants.REASON],
        equals(OTelFeatureFlagConstants.REASON_DEFAULT),
      );
    });

    test('creates attributes for string flag', () {
      final attributes = OpenTelemetryUtil.createOTelAttributes(
        flagKey: 'test-flag',
        value: 'test-value',
        providerName: 'test-provider',
        variant: 'control',
        reason: OTelFeatureFlagConstants.REASON_TARGETING_MATCH,
      );

      final jsonMap = attributes.toJson();

      expect(jsonMap[OTelFeatureFlagConstants.FLAG_VARIANT], equals('control'));
      expect(
        jsonMap[OTelFeatureFlagConstants.FLAG_VALUE_TYPE],
        equals(OTelFeatureFlagConstants.TYPE_STRING),
      );
      expect(
        jsonMap[OTelFeatureFlagConstants.FLAG_VALUE_STRING],
        equals('test-value'),
      );
      expect(
        jsonMap[OTelFeatureFlagConstants.REASON],
        equals(OTelFeatureFlagConstants.REASON_TARGETING_MATCH),
      );
    });

    test('creates attributes for numeric flags', () {
      final intAttributes = OpenTelemetryUtil.createOTelAttributes(
        flagKey: 'int-flag',
        value: 42,
        providerName: 'test-provider',
      );

      final doubleAttributes = OpenTelemetryUtil.createOTelAttributes(
        flagKey: 'double-flag',
        value: 3.14,
        providerName: 'test-provider',
      );

      expect(
        intAttributes.toJson()[OTelFeatureFlagConstants.FLAG_VALUE_TYPE],
        equals(OTelFeatureFlagConstants.TYPE_INT),
      );
      expect(
        intAttributes.toJson()[OTelFeatureFlagConstants.FLAG_VALUE_INT],
        equals(42),
      );

      expect(
        doubleAttributes.toJson()[OTelFeatureFlagConstants.FLAG_VALUE_TYPE],
        equals(OTelFeatureFlagConstants.TYPE_DOUBLE),
      );
      expect(
        doubleAttributes.toJson()[OTelFeatureFlagConstants.FLAG_VALUE_FLOAT],
        equals(3.14),
      );
    });
  });

  group('OpenTelemetryHook', () {
    test('generates telemetry from evaluation details', () async {
      final otelHook = OTelTestHook(providerName: 'test-provider');

      final evaluationDetails = EvaluationDetails(
        flagKey: 'test-flag',
        value: true,
        evaluationTime: DateTime.now(),
        variant: 'control',
      );

      await otelHook.finally_(
        HookContext(flagKey: 'test-flag', result: true),
        evaluationDetails,
      );

      expect(otelHook.capturedAttributes.length, equals(1));
      expect(
        otelHook.capturedAttributes[0][OTelFeatureFlagConstants.FLAG_KEY],
        equals('test-flag'),
      );
      expect(
        otelHook.capturedAttributes[0][OTelFeatureFlagConstants
            .FLAG_VALUE_BOOLEAN],
        isTrue,
      );
      expect(
        otelHook.capturedAttributes[0][OTelFeatureFlagConstants.FLAG_VARIANT],
        equals('control'),
      );
    });

    test(
      'generates telemetry from context when details not available',
      () async {
        final otelHook = OTelTestHook(providerName: 'test-provider');

        await otelHook.finally_(
          HookContext(flagKey: 'test-flag', result: 'test-value'),
          null,
        );

        expect(otelHook.capturedAttributes.length, equals(1));
        expect(
          otelHook.capturedAttributes[0][OTelFeatureFlagConstants.FLAG_KEY],
          equals('test-flag'),
        );
        expect(
          otelHook.capturedAttributes[0][OTelFeatureFlagConstants
              .FLAG_VALUE_STRING],
          equals('test-value'),
        );
      },
    );

    test('includes error reason when appropriate', () async {
      final otelHook = OTelTestHook(providerName: 'test-provider');

      await otelHook.finally_(
        HookContext(
          flagKey: 'test-flag',
          result: null,
          error: Exception('Test error'),
        ),
        null,
      );

      expect(
        otelHook.capturedAttributes[0][OTelFeatureFlagConstants.REASON],
        equals(OTelFeatureFlagConstants.REASON_ERROR),
      );
    });
  });

  group('LoggingHook', () {
    test('serializes non-JSON values safely', () async {
      final messages = <String>[];
      final hook = LoggingHook(logger: messages.add, includeContext: true);

      await hook.before(
        HookContext(
          flagKey: 'test-flag',
          evaluationContext: {
            'when': DateTime.utc(2026, 4, 20),
            'duration': const Duration(seconds: 5),
            'setLike': {1, 2, 3},
          },
          result: Object(),
        ),
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains('"flagKey":"test-flag"'));
      expect(messages.single, contains('"duration":5000000'));
      expect(messages.single, contains('"setLike":[1,2,3]'));
    });

    test('serializes circular structures without throwing', () async {
      final messages = <String>[];
      final hook = LoggingHook(logger: messages.add, includeContext: true);
      final circular = <String, dynamic>{};
      circular['self'] = circular;

      await hook.before(
        HookContext(
          flagKey: 'test-flag',
          evaluationContext: circular,
          result: circular,
        ),
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains(r'"self":"[Circular]"'));
    });

    test('falls back to an error message when serialization fails', () async {
      final messages = <String>[];
      final hook = LoggingHook(logger: messages.add, includeContext: true);

      await hook.before(
        HookContext(
          flagKey: 'test-flag',
          evaluationContext: {'broken': BrokenStringify()},
        ),
      );

      expect(messages, hasLength(1));
      expect(
        messages.single,
        contains('LoggingHook failed to serialize log for stage: before'),
      );
      expect(messages.single, contains('flag: test-flag'));
    });
  });
}
