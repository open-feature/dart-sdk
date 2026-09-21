import 'dart:async';

import 'details.dart';
import 'error.dart';
import 'evaluation_context.dart';
import 'events.dart';
import 'immutable.dart';
import 'metadata.dart';
import 'provider.dart';

/// A provider for conformance tests and application tests.
final class InMemoryProvider implements FeatureProvider, ProviderEventSource {
  InMemoryProvider([Map<String, Object> flags = const {}])
    : _flags = _copyFlags(flags);

  Map<String, Object> _flags;
  final StreamController<ProviderEvent> _events =
      StreamController<ProviderEvent>.broadcast(sync: true);

  @override
  Stream<ProviderEvent> get events => _events.stream;

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'In-memory Provider');

  /// Replaces the complete flag set and emits a configuration event.
  void replaceAll(Map<String, Object> flags) {
    final previousKeys = _flags.keys.toSet();
    final nextFlags = _copyFlags(flags);
    final changedKeys = <String>{...previousKeys, ...nextFlags.keys}.toList()
      ..sort();
    _flags = nextFlags;
    _events.add(
      ProviderEvent(
        type: ProviderEventType.configurationChanged,
        flagsChanged: changedKeys,
      ),
    );
  }

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, defaultValue);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => _resolve(flagKey, immutableStructure(defaultValue));

  ResolutionDetails<T> _resolve<T>(String flagKey, T defaultValue) {
    if (!_flags.containsKey(flagKey)) {
      return ResolutionDetails<T>(
        value: defaultValue,
        errorCode: ErrorCode.flagNotFound,
        errorMessage: 'Flag "$flagKey" was not found.',
        reason: 'ERROR',
      );
    }

    final value = _flags[flagKey];
    if (value is! T) {
      return ResolutionDetails<T>(
        value: defaultValue,
        errorCode: ErrorCode.typeMismatch,
        errorMessage: 'Flag "$flagKey" has an unexpected type.',
        reason: 'ERROR',
      );
    }

    return ResolutionDetails<T>(value: value, reason: 'STATIC');
  }

  static Map<String, Object> _copyFlags(Map<String, Object> flags) {
    return Map<String, Object>.unmodifiable(
      flags.map((key, value) {
        final copy = immutableValue(value, path: 'flags.$key');
        return MapEntry(key, copy!);
      }),
    );
  }
}
