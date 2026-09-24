import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';

class LateHook implements OpenFeatureHook {
  int calls = 0;
  @override
  void beforeEvaluation(String key, Map<String, dynamic>? context) {
    calls++;
  }

  @override
  void afterEvaluation(
    String key,
    dynamic result,
    Map<String, dynamic>? context,
  ) {}
}

class OrderedHook extends BaseHook {
  final List<String> calls;
  OrderedHook(String name, HookPriority priority, this.calls)
    : super(
        metadata: HookMetadata(name: name, priority: priority),
      );
  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    calls.add(metadata.name);
    return null;
  }
}

class AfterFailure extends BaseHook {
  dynamic finallyValue;
  AfterFailure() : super(metadata: const HookMetadata(name: 'after-failure'));
  @override
  Future<void> after(HookContext context) async {
    throw StateError('after failed');
  }

  @override
  Future<void> finally_(
    HookContext context,
    EvaluationDetails? details, [
    HookHints? hints,
  ]) async {
    finallyValue = details?.value;
  }
}

void main() {
  test('4.4.1 late API registration reaches existing clients', () async {
    final api = OpenFeatureAPI();
    await api.setProviderAndWait(InMemoryProvider({'flag': true}));
    final client = api.getClient('existing');
    addTearDown(client.dispose);
    addTearDown(OpenFeatureAPI.resetInstance);
    final hook = LateHook();
    api.addHooks([hook]);
    await client.getBooleanFlag('flag');
    expect(hook.calls, 1);
  });
  test('4.4.2 SDK uses insertion order irrespective of priority', () async {
    final api = OpenFeatureAPI();
    await api.setProviderAndWait(InMemoryProvider({'flag': true}));
    final client = api.getClient('order');
    addTearDown(client.dispose);
    addTearDown(OpenFeatureAPI.resetInstance);
    final calls = <String>[];
    client.addHook(OrderedHook('first', HookPriority.LOW, calls));
    client.addHook(OrderedHook('second', HookPriority.CRITICAL, calls));
    await client.getBooleanFlag('flag');
    expect(calls, ['first', 'second']);
  });
  test(
    '4.3.8 finally details match the after-failure application default',
    () async {
      final api = OpenFeatureAPI();
      await api.setProviderAndWait(InMemoryProvider({'flag': true}));
      final client = api.getClient('failure');
      addTearDown(client.dispose);
      addTearDown(OpenFeatureAPI.resetInstance);
      final hook = AfterFailure();
      client.addHook(hook);
      final value = await client.getBooleanFlag('flag', defaultValue: false);
      expect(value, false);
      expect(hook.finallyValue, value);
    },
  );
}
