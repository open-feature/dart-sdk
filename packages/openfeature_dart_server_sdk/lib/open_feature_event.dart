import 'dart:async';

import 'feature_provider.dart';

/// A typed handler may finish synchronously or asynchronously.
typedef EventHandler = FutureOr<void> Function(OpenFeatureEvent event);

/// OpenFeature specification-compliant event types
enum OpenFeatureEventType {
  PROVIDER_READY,
  PROVIDER_ERROR,
  PROVIDER_CONFIGURATION_CHANGED,
  PROVIDER_STALE,
  PROVIDER_CONTEXT_CHANGED,
  PROVIDER_RECONCILING,
}

class OpenFeatureEvent {
  final OpenFeatureEventType type;
  final String message;
  final dynamic data;
  final DateTime timestamp;
  final ProviderMetadata? providerMetadata;
  final FeatureProvider? provider;
  final String? domain;
  final ErrorCode? errorCode;
  final List<String>? flagsChanged;
  final Map<String, Object> eventMetadata;

  String? get providerName => providerMetadata?.name ?? provider?.metadata.name;
  String? get errorMessage =>
      type == OpenFeatureEventType.PROVIDER_ERROR ? message : null;

  OpenFeatureEvent(
    this.type,
    this.message, {
    this.data,
    this.providerMetadata,
    this.provider,
    this.domain,
    this.errorCode,
    List<String>? flagsChanged,
    Map<String, Object> eventMetadata = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now(),
       flagsChanged = flagsChanged == null
           ? null
           : List.unmodifiable(flagsChanged),
       eventMetadata = Map.unmodifiable(eventMetadata) {
    for (final value in eventMetadata.values) {
      if (value is! bool && value is! String && value is! num) {
        throw ArgumentError(
          'Event metadata values must be boolean, string or number.',
        );
      }
    }
  }
}
