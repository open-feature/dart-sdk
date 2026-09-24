import 'dart:async';

import 'feature_provider.dart';

/// Lifecycle event types emitted by v0.9-capable providers.
enum ProviderLifecycleEventType {
  PROVIDER_READY,
  PROVIDER_ERROR,
  PROVIDER_CONFIGURATION_CHANGED,
  PROVIDER_STALE,
  PROVIDER_CONTEXT_CHANGED,
  PROVIDER_RECONCILING,
}

/// A lifecycle event emitted directly by a feature provider.
class ProviderLifecycleEvent {
  final ProviderLifecycleEventType type;
  final String message;
  final dynamic data;
  final ErrorCode? errorCode;
  final DateTime timestamp;

  ProviderLifecycleEvent(
    this.type,
    this.message, {
    this.data,
    this.errorCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Optional capability for providers that own their v0.9 lifecycle events.
///
/// Providers implementing this interface must emit
/// [ProviderLifecycleEventType.PROVIDER_READY] when initialization completes
/// normally and [ProviderLifecycleEventType.PROVIDER_ERROR] when it completes
/// abnormally. OpenFeature v0.9 requires the corresponding event to be emitted
/// before `initialize` terminates. The SDK temporarily tolerates delivery
/// shortly afterward only for legacy [FeatureProvider] implementations. New
/// ProviderInitialization capabilities receive no post-return grace.
/// Providers without initialization need not emit initialization events.
/// Legacy providers lacking this interface use LegacyProviderLifecycleAdapter
/// compatibility, deriving events from lifecycle return values.
abstract interface class ProviderEventSource {
  Stream<ProviderLifecycleEvent> get providerEvents;
}

/// Marker for provider instances that can be bound to only one domain.
abstract interface class DomainScopedProvider {}
