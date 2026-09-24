import 'dart:async';

import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart'
    show createIsolatedOpenFeatureAPI;
import 'package:test/test.dart';

void main() {
  late OpenFeatureAPI api;
  setUp(() => api = createIsolatedOpenFeatureAPI());
  tearDown(() => api.shutdown());

  test('1.4.11: evaluation does not print for provider errors', () async {
    final messages = <String>[];
    await api.setProviderAndWait(_Provider()..error = true);
    runZoned(
      () {
        expect(api.getClient().getBooleanValue('flag', false), isFalse);
        expect(
          api.getClient().getBooleanDetails('flag', false).errorCode,
          ErrorCode.general,
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, message) => messages.add(message),
      ),
    );
    expect(messages, isEmpty);
  });

  test(
    '1.8.2: isolated APIs separate context hooks events and shutdown',
    () async {
      final other = createIsolatedOpenFeatureAPI();
      addTearDown(other.shutdown);
      final first = _Provider();
      final second = _Provider();
      await api.setEvaluationContextForDomainAndWait(
        'same',
        EvaluationContext(targetingKey: 'first'),
      );
      await other.setEvaluationContextForDomainAndWait(
        'same',
        EvaluationContext(targetingKey: 'second'),
      );
      var firstHooks = 0;
      var secondHooks = 0;
      var firstEvents = 0;
      var secondEvents = 0;
      api.addHooks([_Hook(beforeCall: (_, _) => firstHooks++)]);
      other.addHooks([_Hook(beforeCall: (_, _) => secondHooks++)]);
      api.addHandler(ProviderEventType.ready, (_) => firstEvents++);
      other.addHandler(ProviderEventType.ready, (_) => secondEvents++);
      await api.setProviderForDomainAndWait('same', first);
      expect(secondEvents, 0);
      await other.setProviderForDomainAndWait('same', second);
      api.getClient('same').getBooleanValue('flag', false);
      other.getClient('same').getBooleanValue('flag', false);
      expect(first.resolvedContext.targetingKey, 'first');
      expect(second.resolvedContext.targetingKey, 'second');
      expect(
        [firstHooks, secondHooks, firstEvents, secondEvents],
        [1, 1, 1, 1],
      );
      await api.shutdown();
      expect(first.shutdownCalls, 1);
      expect(second.shutdownCalls, 0);
      expect(other.getClient('same').providerStatus, ProviderStatus.ready);
      expect(other.getClient('same').getBooleanValue('flag', false), isTrue);
      expect(second.resolvedContext.targetingKey, 'second');
      expect(secondHooks, 2);
    },
  );

  test('4.2.2.2 and 4.2.2.3: hook metadata fields reject mutation', () async {
    await api.setProviderForDomainAndWait('checkout', _Provider());
    final seen = <String>[];
    api.addHooks([
      _Hook(
        beforeCall: (context, _) {
          final dynamic client = context.clientMetadata;
          final dynamic provider = context.providerMetadata;
          // Deliberately bypass static typing to verify runtime immutability.
          // ignore: avoid_dynamic_calls
          expect(() => client.domain = 'changed', throwsNoSuchMethodError);
          // ignore: avoid_dynamic_calls
          expect(() => provider.name = 'changed', throwsNoSuchMethodError);
          seen.add(context.clientMetadata.domain!);
          seen.add(context.providerMetadata.name);
        },
      ),
    ]);
    expect(api.getClient('checkout').getBooleanValue('flag', false), isTrue);
    expect(seen, ['checkout', 'evidence-provider']);
  });

  test('1.4 and 2.2: detailed resolution preserves provider fields', () async {
    final provider = _Provider();
    await api.setProviderAndWait(provider);
    final FlagEvaluationDetails<bool> details = api
        .getClient()
        .getBooleanDetails('requested-key', false);
    expect(details.flagKey, 'requested-key');
    expect(details.value, isTrue);
    expect(details.variant, 'enabled');
    expect(details.reason, 'TARGETING_MATCH');
    expect(details.errorCode, isNull);
    expect(details.errorMessage, isNull);
    expect(details.flagMetadata, {
      'source': 'fixture',
      'cached': true,
      'age': 2,
    });
    expect(() => details.flagMetadata.clear(), throwsUnsupportedError);
    provider.error = true;
    final failed = api.getClient().getBooleanDetails('requested-key', false);
    expect(failed.value, isFalse);
    expect(failed.errorCode, ErrorCode.general);
    expect(failed.errorMessage, 'controlled resolution failure');
    expect(failed.reason, 'ERROR');
  });

  test('1.7 and 2.4.4: domain and every status precede handlers', () async {
    final provider = _Provider();
    final client = api.getClient('checkout');
    expect(client.providerStatus, ProviderStatus.notReady);
    await api.setProviderForDomainAndWait('checkout', provider);
    expect(provider.domain, 'checkout');
    expect(client.providerStatus, ProviderStatus.ready);
    final statuses = <ProviderStatus>[];
    for (final type in [
      ProviderEventType.stale,
      ProviderEventType.reconciling,
      ProviderEventType.contextChanged,
      ProviderEventType.error,
    ]) {
      client.addHandler(type, (_) => statuses.add(client.providerStatus));
    }
    provider.emit(ProviderEventType.stale);
    provider.emit(ProviderEventType.reconciling);
    provider.emit(ProviderEventType.contextChanged);
    provider.emit(ProviderEventType.error);
    provider.emit(ProviderEventType.error, errorCode: ErrorCode.providerFatal);
    expect(statuses, [
      ProviderStatus.stale,
      ProviderStatus.reconciling,
      ProviderStatus.ready,
      ProviderStatus.error,
      ProviderStatus.fatal,
    ]);
    await api.shutdown();
    expect(client.providerStatus, ProviderStatus.notReady);
  });

  test('3.1.2: context supports every normative field kind', () {
    final date = DateTime.utc(2026);
    final context = EvaluationContext(
      targetingKey: 'subject',
      attributes: {
        'bool': true,
        'string': 'text',
        'integer': 4,
        'double': 4.2,
        'date': date,
        'structure': {
          'nested': [true, 'text', 3],
        },
      },
    );
    expect(context.getValue('date'), date);
    expect(context.asMap(), {
      'targetingKey': 'subject',
      'bool': true,
      'string': 'text',
      'integer': 4,
      'double': 4.2,
      'date': date,
      'structure': {
        'nested': [true, 'text', 3],
      },
    });
  });

  test('4.1 through 4.6: hook data isolation and immutable hints', () async {
    await api.setProviderForDomainAndWait('checkout', _Provider());
    final context = EvaluationContext(targetingKey: 'subject');
    // A provider without reconciliation still receives the active context.
    await api.setEvaluationContextForDomainAndWait('checkout', context);
    final contexts = <HookContext>[];
    final opaque = Object();
    var afterCount = 0;
    var finalCount = 0;
    Hook makeHook(String id) => _Hook(
      beforeCall: (c, h) {
        expect(c.flagKey, 'flag');
        expect(c.defaultValue, false);
        expect(c.flagValueType, FlagValueType.boolean);
        expect(c.clientMetadata.domain, 'checkout');
        expect(c.providerMetadata.name, 'evidence-provider');
        expect(c.evaluationContext, same(context));
        expect(c.hookData, isEmpty);
        c.hookData['id'] = id;
        c.hookData['opaque'] = opaque;
        contexts.add(c);
        expect(h['date'], DateTime.utc(2026));
        expect(() => h.values['changed'] = true, throwsUnsupportedError);
        expect(
          () => (h['nested']! as Map)['value'] = 2,
          throwsUnsupportedError,
        );
      },
      afterCall: (c, d, h) {
        expect(c.hookData['id'], id);
        expect(c.hookData['opaque'], same(opaque));
        expect(d.value, isTrue);
        afterCount++;
      },
      finallyCall: (c, d, h) {
        expect(c.hookData['id'], id);
        finalCount++;
      },
    );
    api.addHooks([makeHook('api')]);
    final client = api.getClient('checkout')..addHooks([makeHook('client')]);
    final options = EvaluationOptions(
      hookHints: {
        'date': DateTime.utc(2026),
        'nested': {'value': 1},
        'bool': true,
        'string': 'hint',
        'double': 2.5,
      },
    );
    client.getBooleanValue('flag', false, options: options);
    client.getBooleanValue('flag', false, options: options);
    expect(contexts.toSet(), hasLength(4));
    expect(afterCount, 4);
    expect(finalCount, 4);
  });

  test(
    '4.4.3 through 4.4.6: after error preserves remaining cleanup',
    () async {
      await api.setProviderAndWait(_Provider());
      final calls = <String>[];
      api.addHooks([
        _Hook(
          afterCall: (_, _, _) => calls.add('first.after'),
          errorCall: (_, _, _) => calls.add('first.error'),
          finallyCall: (_, _, _) => calls.add('first.finally'),
        ),
        _Hook(
          afterCall: (_, _, _) {
            calls.add('second.after');
            throw StateError('after');
          },
          errorCall: (_, _, _) {
            calls.add('second.error');
            throw StateError('error');
          },
          finallyCall: (_, _, _) {
            calls.add('second.finally');
            throw StateError('finally');
          },
        ),
      ]);
      expect(api.getClient().getBooleanValue('flag', false), isFalse);
      expect(calls, [
        'second.after',
        'second.error',
        'first.error',
        'second.finally',
        'first.finally',
      ]);
    },
  );

  test(
    '1.1.7 and 1.6.2: shutdown clears API state and permits reuse',
    () async {
      final global = _Provider();
      final domain = _Provider();
      await api.setEvaluationContextAndWait(
        EvaluationContext(targetingKey: 'global'),
      );
      await api.setEvaluationContextForDomainAndWait(
        'checkout',
        EvaluationContext(targetingKey: 'domain'),
      );
      await api.setProviderAndWait(global);
      await api.setProviderForDomainAndWait('checkout', domain);
      var hooks = 0;
      var events = 0;
      api.addHooks([_Hook(beforeCall: (_, _) => hooks++)]);
      api.addHandler(ProviderEventType.ready, (_) => events++);
      api.getClient().getBooleanValue('flag', false);
      final previousEvents = events;
      await api.shutdown();
      expect(global.shutdownCalls, 1);
      expect(domain.shutdownCalls, 1);
      expect(api.getClient().providerStatus, ProviderStatus.notReady);
      expect(api.getClient('checkout').providerStatus, ProviderStatus.notReady);
      final replacement = _Provider();
      await api.setProviderAndWait(replacement);
      expect(replacement.initialContext.asMap(), isEmpty);
      api.getClient('checkout').getBooleanValue('flag', false);
      expect(replacement.resolvedContext.asMap(), isEmpty);
      expect(hooks, 1);
      expect(events, previousEvents);
    },
  );

  test(
    '6.1.4: unsupported tracking is a no-op before and after registration',
    () async {
      expect(() => api.getClient().track('event'), returnsNormally);
      await api.setProviderAndWait(_Provider());
      expect(
        () => api.getClient().track(
          'event',
          details: TrackingEventDetails(value: 2),
        ),
        returnsNormally,
      );
    },
  );
}

final class _Provider
    implements
        FeatureProvider,
        InitializableProvider,
        ProviderEventSource,
        ShutdownProvider,
        DomainScopedProvider {
  final controller = StreamController<ProviderEvent>.broadcast(sync: true);
  final delegate = InMemoryProvider();
  bool error = false;
  int shutdownCalls = 0;
  String? domain;
  EvaluationContext initialContext = EvaluationContext.empty;
  EvaluationContext resolvedContext = EvaluationContext.empty;
  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'evidence-provider');
  @override
  Stream<ProviderEvent> get events => controller.stream;
  void emit(ProviderEventType type, {ErrorCode? errorCode}) =>
      controller.add(ProviderEvent(type: type, errorCode: errorCode));
  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) async {
    initialContext = context;
    this.domain = domain;
    emit(ProviderEventType.ready);
  }

  @override
  Future<void> shutdown() async {
    shutdownCalls++;
    await controller.close();
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String key,
    bool fallback,
    EvaluationContext context,
  ) {
    resolvedContext = context;
    return ResolutionDetails(
      value: true,
      variant: 'enabled',
      reason: 'TARGETING_MATCH',
      errorCode: error ? ErrorCode.general : null,
      errorMessage: error ? 'controlled resolution failure' : null,
      flagMetadata: {'source': 'fixture', 'cached': true, 'age': 2},
    );
  }

  @override
  ResolutionDetails<String> resolveStringValue(
    String key,
    String fallback,
    EvaluationContext context,
  ) => delegate.resolveStringValue(key, fallback, context);
  @override
  ResolutionDetails<int> resolveIntegerValue(
    String key,
    int fallback,
    EvaluationContext context,
  ) => delegate.resolveIntegerValue(key, fallback, context);
  @override
  ResolutionDetails<double> resolveDoubleValue(
    String key,
    double fallback,
    EvaluationContext context,
  ) => delegate.resolveDoubleValue(key, fallback, context);
  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String key,
    Map<String, Object?> fallback,
    EvaluationContext context,
  ) => delegate.resolveStructureValue(key, fallback, context);
}

final class _Hook extends HookAdapter {
  _Hook({this.beforeCall, this.afterCall, this.errorCall, this.finallyCall});
  final void Function(HookContext, HookHints)? beforeCall;
  final void Function(HookContext, FlagEvaluationDetails<Object>, HookHints)?
  afterCall;
  final void Function(HookContext, Object, HookHints)? errorCall;
  final void Function(HookContext, FlagEvaluationDetails<Object>, HookHints)?
  finallyCall;
  @override
  void before(HookContext c, HookHints h) => beforeCall?.call(c, h);
  @override
  void after(HookContext c, FlagEvaluationDetails<Object> d, HookHints h) =>
      afterCall?.call(c, d, h);
  @override
  void error(HookContext c, Object e, HookHints h) => errorCall?.call(c, e, h);
  @override
  void finallyAfter(
    HookContext c,
    FlagEvaluationDetails<Object> d,
    HookHints h,
  ) => finallyCall?.call(c, d, h);
}
