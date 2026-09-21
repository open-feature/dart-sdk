import 'details.dart';
import 'error.dart';
import 'evaluation_context.dart';
import 'metadata.dart';
import 'provider.dart';

final class NoOpProvider implements FeatureProvider {
  const NoOpProvider();

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'No-op Provider');

  @override
  ResolutionDetails<bool> resolveBooleanValue(
    String flagKey,
    bool defaultValue,
    EvaluationContext context,
  ) => _details(defaultValue);

  @override
  ResolutionDetails<double> resolveDoubleValue(
    String flagKey,
    double defaultValue,
    EvaluationContext context,
  ) => _details(defaultValue);

  @override
  ResolutionDetails<int> resolveIntegerValue(
    String flagKey,
    int defaultValue,
    EvaluationContext context,
  ) => _details(defaultValue);

  @override
  ResolutionDetails<String> resolveStringValue(
    String flagKey,
    String defaultValue,
    EvaluationContext context,
  ) => _details(defaultValue);

  @override
  ResolutionDetails<Map<String, Object?>> resolveStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue,
    EvaluationContext context,
  ) => _details(defaultValue);

  ResolutionDetails<T> _details<T>(T defaultValue) {
    return ResolutionDetails<T>(
      value: defaultValue,
      errorCode: ErrorCode.providerNotReady,
      errorMessage: 'No provider has been configured.',
      reason: 'ERROR',
    );
  }
}
