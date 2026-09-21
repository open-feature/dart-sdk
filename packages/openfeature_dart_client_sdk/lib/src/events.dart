import 'error.dart';
import 'immutable.dart';
import 'metadata.dart';

/// Provider lifecycle and configuration events.
enum ProviderEventType {
  ready,
  error,
  configurationChanged,
  stale,
  reconciling,
  contextChanged,
}

/// Event data emitted by a feature provider.
final class ProviderEvent {
  ProviderEvent({
    required this.type,
    Iterable<String> flagsChanged = const [],
    this.message,
    this.errorCode,
    Map<String, Object> metadata = const {},
  }) : flagsChanged = List<String>.unmodifiable(flagsChanged),
       metadata = immutableMetadata(metadata, path: 'eventMetadata');

  final ProviderEventType type;
  final List<String> flagsChanged;
  final String? message;
  final ErrorCode? errorCode;
  final Map<String, Object> metadata;
}

/// Event data delivered by the SDK to API and client handlers.
final class ProviderEventDetails {
  ProviderEventDetails({
    required this.type,
    required this.providerMetadata,
    this.domain,
    Iterable<String> flagsChanged = const [],
    this.message,
    this.errorCode,
    Map<String, Object> metadata = const {},
  }) : flagsChanged = List<String>.unmodifiable(flagsChanged),
       metadata = immutableMetadata(metadata, path: 'eventMetadata');

  final ProviderEventType type;
  final ProviderMetadata providerMetadata;
  final String? domain;
  final List<String> flagsChanged;
  final String? message;
  final ErrorCode? errorCode;
  final Map<String, Object> metadata;
}

/// Receives one provider event after the SDK updates provider status.
typedef ProviderEventHandler = void Function(ProviderEventDetails details);
