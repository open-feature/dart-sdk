import 'dart:async';
import 'dart:collection';
import 'package:meta/meta.dart';

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

  TransactionContextManager._internal();

  factory TransactionContextManager() => _instance;

  /// Independent propagation state for an isolated API instance.
  TransactionContextManager.isolated();

  _TransactionState get _state {
    final state =
        Zone.current[_zoneStateKey] as _TransactionState? ?? _fallback;
    if (state.generation != _generation) {
      state.contexts.clear();
      state.stack.clear();
      state.generation = _generation;
    }
    return state;
  }

  Map<String, TransactionContext> get _contexts => _state.contexts;

  List<String> get _contextStack => _state.stack;

  TransactionContext? get currentContext {
    if (_contextStack.isEmpty) return null;
    return _contexts[_contextStack.last];
  }

  void pushContext(TransactionContext context, {Duration? timeout}) {
    _contexts[context.transactionId] = context;
    _contextStack.add(context.transactionId);
    _ownedContexts.add(context);
    context.scheduleCleanup(timeout ?? const Duration(minutes: 5));
  }

  TransactionContext? popContext() {
    if (_contextStack.isEmpty) return null;
    final contextId = _contextStack.removeLast();
    final context = _contexts.remove(contextId);
    context?.cleanup();
    _ownedContexts.remove(context);
    return context;
  }

  void clearContext(String transactionId) {
    final context = _contexts.remove(transactionId);
    if (context != null) {
      _contextStack.remove(transactionId);
      context.cleanup();
      _ownedContexts.remove(context);
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
    final state = _TransactionState(generation)
      ..contexts.addAll(_contexts)
      ..stack.addAll(_contextStack);

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
    Object? firstError;
    StackTrace? firstStack;
    for (final context in _ownedContexts) {
      try {
        context.cleanup();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    _ownedContexts.clear();
    _generation++;
    _fallback.contexts.clear();
    _fallback.stack.clear();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }
}

class _TransactionState {
  int generation;
  final contexts = <String, TransactionContext>{};
  final stack = <String>[];
  _TransactionState(this.generation);
}
