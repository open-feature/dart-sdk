import 'details.dart';
import 'evaluation_context.dart';
import 'immutable.dart';
import 'metadata.dart';

/// The type expected from a typed flag evaluation.
enum FlagValueType { boolean, string, integer, double, structure }

/// Immutable hook hints supplied with one flag evaluation.
final class HookHints {
  HookHints([Map<String, Object?> values = const {}])
    : values = immutableStructure(values, path: 'hookHints');

  final Map<String, Object?> values;

  Object? operator [](String key) => values[key];
}

/// Context available to an evaluation hook.
final class HookContext {
  HookContext({
    required this.flagKey,
    required Object defaultValue,
    required this.flagValueType,
    required this.clientMetadata,
    required this.providerMetadata,
    required this.evaluationContext,
  }) : defaultValue = immutableValue(defaultValue, path: 'defaultValue')!;

  final String flagKey;
  final Object defaultValue;
  final FlagValueType flagValueType;
  final ClientMetadata clientMetadata;
  final ProviderMetadata providerMetadata;
  final EvaluationContext evaluationContext;

  /// Mutable data shared by hook stages for this evaluation only.
  final Map<String, Object?> hookData = <String, Object?>{};
}

/// A synchronous hook for the static-context evaluation path.
abstract interface class Hook {
  void before(HookContext context, HookHints hints);

  void after(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  );

  void error(HookContext context, Object error, HookHints hints);

  void finallyAfter(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  );
}

/// Empty hook implementation for consumers that need only selected stages.
abstract base class HookAdapter implements Hook {
  const HookAdapter();

  @override
  void after(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {}

  @override
  void before(HookContext context, HookHints hints) {}

  @override
  void error(HookContext context, Object error, HookHints hints) {}

  @override
  void finallyAfter(
    HookContext context,
    FlagEvaluationDetails<Object> details,
    HookHints hints,
  ) {}
}

/// Per-evaluation options for hooks and hook hints.
final class EvaluationOptions {
  EvaluationOptions({
    Iterable<Hook> hooks = const [],
    Map<String, Object?> hookHints = const {},
  }) : hooks = List<Hook>.unmodifiable(hooks),
       hookHints = HookHints(hookHints);

  final List<Hook> hooks;
  final HookHints hookHints;
}
