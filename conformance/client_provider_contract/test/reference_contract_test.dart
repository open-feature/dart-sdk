// This reference proves the harness runs. It is not an independent provider.
import 'dart:async';
import 'package:openfeature_client_provider_contract/client_provider_contract.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:test/test.dart';

void main() => runClientProviderContract(
  providerName: 'SDK reference fixture (not external-provider evidence)',
  createFixture: ReferenceFixture.new,
);

class HeldResponse implements HeldProviderResponse {
  final entered = Completer<void>();
  final completed = Completer<void>();
  @override
  Future<void> get started => entered.future;
  @override
  void release() {
    if (!completed.isCompleted) completed.complete();
  }
}

class ReferenceFixture
    implements
        ClientProviderFixture,
        FeatureProvider,
        InitializableProvider,
        ContextReconciliationProvider,
        ProviderEventSource,
        ShutdownProvider {
  final bySubject = <String?, Map<String, Object>>{};
  final delegate = InMemoryProvider();
  final controller = StreamController<ProviderEvent>.broadcast(sync: true);
  final held = <HeldResponse>[];
  HeldResponse? next;
  bool fail = false;
  int generation = 0;
  EvaluationContext context = EvaluationContext.empty;
  @override
  int shutdownCalls = 0;
  @override
  FeatureProvider get provider => this;
  @override
  ProviderMetadata get metadata => const ProviderMetadata(name: 'reference');
  @override
  Stream<ProviderEvent> get events => controller.stream;
  @override
  void setFlags(String? subject, Map<String, Object> flags) =>
      bySubject[subject] = Map.of(flags);
  @override
  void failNextRequest() => fail = true;
  @override
  HeldProviderResponse holdNextResponse() {
    final response = HeldResponse();
    held.add(response);
    next = response;
    return response;
  }

  Future<void> load(EvaluationContext target, ProviderEventType success) async {
    final revision = ++generation;
    final flags = Map<String, Object>.of(bySubject[target.targetingKey] ?? {});
    final response = next;
    next = null;
    if (response != null) {
      response.entered.complete();
      await response.completed.future;
    }
    if (revision != generation) return;
    if (fail) {
      fail = false;
      controller.add(
        ProviderEvent(
          type: ProviderEventType.error,
          errorCode: ErrorCode.general,
          message: 'Controlled failure',
        ),
      );
      throw StateError('Controlled transport failure');
    }
    context = target;
    delegate.replaceAll(flags);
    controller.add(ProviderEvent(type: success));
  }

  @override
  Future<void> initialize(EvaluationContext context, {String? domain}) =>
      load(context, ProviderEventType.ready);
  @override
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  ) {
    controller.add(ProviderEvent(type: ProviderEventType.reconciling));
    return load(newContext, ProviderEventType.contextChanged);
  }

  @override
  Future<void> refresh() async {
    await load(context, ProviderEventType.ready);
    controller.add(ProviderEvent(type: ProviderEventType.configurationChanged));
  }

  @override
  Future<void> shutdown() async {
    generation++;
    shutdownCalls++;
  }

  @override
  Future<void> close() async {
    try {
      expect(
        shutdownCalls,
        1,
        reason: 'Provider shutdown must precede transport cleanup',
      );
    } finally {
      for (final response in held) {
        response.release();
      }
      await controller.close();
    }
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String key,
    bool fallback,
    EvaluationContext context,
  ) => delegate.resolveBooleanValue(key, fallback, context);
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
  ResolutionDetails<String> resolveStringValue(
    String key,
    String fallback,
    EvaluationContext context,
  ) => delegate.resolveStringValue(key, fallback, context);
  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String key,
    Map<String, Object?> fallback,
    EvaluationContext context,
  ) => delegate.resolveStructureValue(key, fallback, context);
}
