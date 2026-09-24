import 'dart:async';

import '../evaluation_context.dart';
import '../feature_provider.dart';
import '../hooks.dart';
import '../provider_lifecycle.dart';
import '../provider_capabilities.dart';

/// SDK bridge from the minimal [Provider] contract to legacy client internals.
/// API registration reuses one adapter per provider identity. Existing
/// [FeatureProvider] objects retain their original identity without wrapping.
class ResolverProviderAdapter
    implements
        FeatureProvider,
        ProviderEventSource,
        ProviderInitialization,
        ProviderShutdown {
  final Provider delegate;
  ProviderState _state;
  Future<void>? _shutdownFuture;

  factory ResolverProviderAdapter(Provider provider) {
    if (provider is DomainScopedProvider) {
      if (provider is! ProviderInitialization) {
        throw ArgumentError(
          'A domain-scoped provider must implement '
          'ProviderInitialization to receive its bound domain.',
        );
      }
      return _DomainScopedResolverProviderAdapter(provider);
    }
    return ResolverProviderAdapter._(provider);
  }

  ResolverProviderAdapter._(this.delegate)
    : _state = delegate is ProviderInitialization
          ? ProviderState.NOT_READY
          : ProviderState.READY;

  bool get requiresInitialization => delegate is ProviderInitialization;
  List<Hook> get providerHooks => delegate is ProviderHooks
      ? List<Hook>.unmodifiable((delegate as ProviderHooks).hooks)
      : const [];

  @override
  ProviderMetadata get metadata => delegate.metadata;
  @override
  String get name => metadata.name;
  @override
  ProviderConfig get config => const ProviderConfig();
  @override
  ProviderState get state => _state;
  @override
  Stream<ProviderLifecycleEvent> get providerEvents =>
      delegate is ProviderEventSource
      ? (delegate as ProviderEventSource).providerEvents.map((event) {
          _state = switch (event.type) {
            ProviderLifecycleEventType.PROVIDER_READY => ProviderState.READY,
            ProviderLifecycleEventType.PROVIDER_ERROR =>
              event.errorCode == ErrorCode.PROVIDER_FATAL
                  ? ProviderState.FATAL
                  : ProviderState.ERROR,
            ProviderLifecycleEventType.PROVIDER_STALE => ProviderState.STALE,
            _ => _state,
          };
          return event;
        })
      : const Stream.empty();

  @override
  Future<void> initializeProvider(
    EvaluationContext context, {
    String? domain,
  }) async {
    _shutdownFuture = null;
    if (delegate case final ProviderInitialization initialization) {
      await initialization.initializeProvider(
        context.snapshot(),
        domain: domain,
      );
    }
  }

  /// Compatibility entry for clients constructed directly with an adapter.
  @override
  Future<void> initialize([Map<String, dynamic>? config]) =>
      initializeProvider(EvaluationContext.immutable(attributes: config ?? {}));
  @override
  Future<void> connect() => initialize();
  @override
  Future<void> shutdown() => shutdownProvider();
  @override
  Future<void> shutdownProvider() => _shutdownFuture ??= _shutdown();

  Future<void> _shutdown() async {
    try {
      if (delegate case final ProviderShutdown shutdown) {
        await shutdown.shutdownProvider();
      }
    } finally {
      _state = requiresInitialization
          ? ProviderState.NOT_READY
          : ProviderState.READY;
    }
  }

  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    if (delegate case final ProviderTracking tracking) {
      await tracking.trackEvent(
        trackingEventName,
        evaluationContext: evaluationContext,
        trackingDetails: trackingDetails,
      );
    }
  }

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) => delegate.getBooleanFlag(key, defaultValue, context: context);
  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String key,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) => delegate.getStringFlag(key, defaultValue, context: context);
  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String key,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) => delegate.getIntegerFlag(key, defaultValue, context: context);
  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String key,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) => delegate.getDoubleFlag(key, defaultValue, context: context);
  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String key,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) => delegate.getObjectFlag(key, defaultValue, context: context);
}

class _DomainScopedResolverProviderAdapter extends ResolverProviderAdapter
    implements DomainScopedProvider {
  _DomainScopedResolverProviderAdapter(super.provider) : super._();
}

List<Hook> providerHooksFor(FeatureProvider provider) {
  if (provider is ResolverProviderAdapter) return provider.providerHooks;
  if (provider is ProviderHooks)
    return List<Hook>.unmodifiable((provider as ProviderHooks).hooks);
  return const [];
}
