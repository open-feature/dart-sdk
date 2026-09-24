/// Experimental transaction propagation for dynamic-context applications.
library;

import 'dart:async';
import '../evaluation_context.dart';

/// A request-local carrier. Implementations must isolate overlapping requests.
abstract interface class TransactionContextPropagator {
  EvaluationContext? getTransactionContext();

  Future<T> setTransactionContext<T>(
    EvaluationContext context,
    FutureOr<T> Function() operation,
  );
}

/// Dart zone carrier: nested scopes restore their parent after completion.
/// Use one instance per API; zones do not propagate across Dart isolates.
final class ZoneTransactionContextPropagator
    implements TransactionContextPropagator {
  final Object _key = Object();

  @override
  EvaluationContext? getTransactionContext() =>
      Zone.current[_key] as EvaluationContext?;

  @override
  Future<T> setTransactionContext<T>(
    EvaluationContext context,
    FutureOr<T> Function() operation,
  ) async => await runZoned(operation, zoneValues: {_key: context.snapshot()});
}
