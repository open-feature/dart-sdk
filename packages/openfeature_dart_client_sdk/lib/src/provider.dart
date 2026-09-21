import 'details.dart';
import 'evaluation_context.dart';
import 'events.dart';
import 'hooks.dart';
import 'immutable.dart';
import 'metadata.dart';

/// Current provider status for the static-context paradigm.
enum ProviderStatus { notReady, ready, reconciling, stale, error, fatal }

/// Resolves typed flag values from local provider state.
abstract interface class FeatureProvider {
  ProviderMetadata get metadata;

  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  );

  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  );

  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  );

  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  );

  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  );
}

/// Optional provider initialization capability.
abstract interface class InitializableProvider {
  Future<void> initialize(EvaluationContext context, {String? domain});
}

/// Optional provider shutdown capability.
abstract interface class ShutdownProvider {
  Future<void> shutdown();
}

/// Optional provider context-reconciliation capability.
abstract interface class ContextReconciliationProvider {
  Future<void> onContextChanged(
    EvaluationContext previousContext,
    EvaluationContext newContext,
  );
}

/// Marks a provider instance as valid for one domain only.
abstract interface class DomainScopedProvider {}

/// Optional provider event capability.
abstract interface class ProviderEventSource {
  Stream<ProviderEvent> get events;
}

/// Optional provider hooks capability.
abstract interface class ProviderHooks {
  List<Hook> get hooks;
}

/// Optional provider tracking capability.
abstract interface class TrackingProvider {
  void track(
    String trackingEventName,
    EvaluationContext context, {
    TrackingEventDetails? details,
  });
}

/// Data associated with one tracking call.
final class TrackingEventDetails {
  TrackingEventDetails({this.value, Map<String, Object?> attributes = const {}})
    : attributes = immutableStructure(attributes, path: 'trackingAttributes');

  final num? value;
  final Map<String, Object?> attributes;
}
