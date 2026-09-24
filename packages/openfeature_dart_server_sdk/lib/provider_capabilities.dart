import 'dart:async';

import 'evaluation_context.dart';
import 'feature_provider.dart';
import 'hooks.dart';
import 'provider_lifecycle.dart';

/// Optional v0.9 initialization. Lifecycle support includes provider-owned
/// events, which must be emitted before initialization terminates (2.8.2-4).
abstract interface class ProviderInitialization implements ProviderEventSource {
  Future<void> initializeProvider(EvaluationContext context, {String? domain});
}

/// Optional resource cleanup. Implementations should be idempotent (2.5.3).
abstract interface class ProviderShutdown {
  Future<void> shutdownProvider();
}

/// Provider-owned hooks participate after application before hooks and before
/// application after/error/finally hooks (2.3.1).
abstract interface class ProviderHooks {
  List<Hook> get hooks;
}

/// Optional tracking transport. Full tracking details/API work is issue #164.
abstract interface class ProviderTracking {
  Future<void> trackEvent(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  });
}

/// Named compatibility policy for the original [FeatureProvider] interface.
/// Legacy initialize still receives its original configuration signature, not
/// a context disguised as vendor configuration. Eventful legacy providers
/// retain a bounded delivery grace; new capability providers get no grace.
abstract final class LegacyProviderLifecycleAdapter {
  static const eventDeliveryGrace = Duration(seconds: 1);
  static Future<void> initialize(FeatureProvider provider) =>
      provider.initialize();
  static Future<void> shutdown(FeatureProvider provider) => provider.shutdown();
}
