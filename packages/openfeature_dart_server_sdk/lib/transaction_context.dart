import 'dart:async';
import 'dart:collection';
import 'package:meta/meta.dart';
import 'evaluation_context.dart';
import 'experimental/transaction_context.dart';

/// Transaction context holder
class TransactionContext {
  final String transactionId;
  final Map<String, dynamic> attributes;
  final TransactionContext? parent;
  final DateTime createdAt;
  Timer? _cleanupTimer;

  TransactionContext({
    required this.transactionId,
    required this.attributes,
    this.parent,
  }) : createdAt = DateTime.now();

  Map<String, dynamic> get effectiveAttributes {
    final parentAttrs = parent?.effectiveAttributes ?? {};
    return {...parentAttrs, ...attributes};
  }

  void scheduleCleanup(Duration timeout) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(timeout, cleanup);
  }

  @mustCallSuper
  void cleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
}

/// Transaction context manager
class TransactionContextManager {
  static final TransactionContextManager _instance =
      TransactionContextManager._internal();
  final Object _zoneStateKey = Object();
  final _fallback = _TransactionState(0);
  final _ownedContexts = HashSet<TransactionContext>.identity();
  int _generation = 0;
  final Object _propagationScopeKey = Object();
  Object _propagationEpoch = Object();
  TransactionContextPropagator? _propagator;

  /// Experimental carrier registration. Null removes the carrier.
  void setTransactionContextPropagator(
    TransactionContextPropagator? propagator,
  ) {
    _propagationEpoch = Object();
    _propagator = propagator;
  }

  /// Runs the operation even when no carrier has been registered.
  Future<T> setTransactionContext<T>(
    EvaluationContext context,
    FutureOr<T> Function() operation,
  ) async {
    final propagator = _propagator;
    if (propagator == null) return await operation();
    final snapshot = context.snapshot();
    return await runZoned(
      () => propagator.setTransactionContext(snapshot, operation),
      zoneValues: {_propagationScopeKey: _propagationEpoch},
    );
  }

  /// Explicit carriers replace the legacy manager's context while registered.
  Map<String, dynamic> get effectiveContext {
    final scope = Zone.current[_propagationScopeKey];
    if (scope != null && !identical(scope, _propagationEpoch)) return const {};
    final propagator = _propagator;
    if (propagator != null) {
      return propagator.getTransactionContext()?.toProviderContext() ??
          const {};
    }
    return currentContext?.effectiveAttributes ?? const {};
  }

  TransactionContextManager._internal();

  factory TransactionContextManager() => _instance;

  /// Independent propagation state for an isolated API instance.
  TransactionContextManager.isolated();

  _TransactionState get _state {
    final state =
        Zone.current[_zoneStateKey] as _TransactionState? ?? _fallback;
    if (state.generation != _generation) {
      state.stack.clear();
      state.generation = _generation;
    }
    return state;
  }

  List<TransactionContext> get _contextStack => _state.stack;

  TransactionContext? get currentContext {
    if (_contextStack.isEmpty) return null;
    return _contextStack.last;
  }

  void pushContext(TransactionContext context, {Duration? timeout}) {
    _contextStack.add(context);
    _ownedContexts.add(context);
    context.scheduleCleanup(timeout ?? const Duration(minutes: 5));
  }

  TransactionContext? popContext() {
    if (_contextStack.isEmpty) return null;
    final context = _contextStack.removeLast();
    try {
      context.cleanup();
    } finally {
      _ownedContexts.remove(context);
    }
    return context;
  }

  void clearContext(String transactionId) {
    final index = _contextStack.lastIndexWhere(
      (c) => c.transactionId == transactionId,
    );
    if (index >= 0) {
      final context = _contextStack.removeAt(index);
      try {
        context.cleanup();
      } finally {
        _ownedContexts.remove(context);
      }
    }
  }

  TransactionContext createChildContext(
    String transactionId,
    Map<String, dynamic> attributes,
  ) {
    final parent = currentContext;
    return TransactionContext(
      transactionId: transactionId,
      attributes: attributes,
      parent: parent,
    );
  }

  /// Run code with a specific transaction context
  Future<T> withContext<T>(
    String transactionId,
    Map<String, dynamic> attributes,
    Future<T> Function() operation,
  ) async {
    final generation = _generation;
    final state = _TransactionState(generation)..stack.addAll(_contextStack);

    return await runZoned(() async {
      final context = TransactionContext(
        transactionId: transactionId,
        attributes: attributes,
        parent: currentContext,
      );

      pushContext(context);
      try {
        return await operation();
      } finally {
        // A reset invalidates this frame; it must not pop a new context that
        // the caller deliberately established after shutdown in the same zone.
        if (_generation == generation) popContext();
      }
    }, zoneValues: {_zoneStateKey: state});
  }

  void cleanup() {
    setTransactionContextPropagator(null);
    final contexts = _ownedContexts.toList();
    _ownedContexts.clear();
    _generation++;
    _fallback.stack.clear();
    Object? firstError;
    StackTrace? firstStack;
    for (final context in contexts) {
      try {
        context.cleanup();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }
}

class _TransactionState {
  int generation;
  final stack = <TransactionContext>[];
  _TransactionState(this.generation);
}
